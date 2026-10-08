import AVFoundation
import BashCutAutomation
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
import Foundation

/// A voice take file and the provenance it was made with (P0-C4, flexibility audit D4): what `voice.speak` writes
/// next to each kept take (`<take>.json`) so `voice.place` can put the take the agent picked on the timeline later.
struct VoiceTakeFile {
    let url: URL
    /// The media's `generatedBy`: plugin, provider, version and the hash of the text it says.
    let generatedBy: [String: JSONValue]
    /// The media's `provenance` (origin ai, request ID and charge when known).
    let provenance: JSONValue

    @MainActor init(_ asset: GeneratedPluginAsset, voice: [String: JSONValue]?) {
        url = asset.url
        generatedBy = ProjectDocument.voiceProvenance(asset, voice: voice)
        provenance = ProjectDocument.voiceTakeProvenance(asset)
    }

    init(url: URL, generatedBy: [String: JSONValue], provenance: JSONValue) {
        self.url = url
        self.generatedBy = generatedBy
        self.provenance = provenance
    }

    var sidecar: URL { url.appendingPathExtension("json") }

    /// Writes the provenance and the voice facts next to the take.
    func write(voice: [String: JSONValue]) throws {
        let value = JSONValue.object(["generatedBy": .object(generatedBy), "provenance": provenance, "voice": .object(voice)])
        try JSONEncoder().encode(value).write(to: sidecar, options: .atomic)
    }

    /// A kept take and its voice facts from its sidecar.
    static func read(_ url: URL) throws -> (VoiceTakeFile, voice: [String: JSONValue]) {
        let sidecar = url.appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: sidecar), let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            let generatedBy = value.object["generatedBy"]?.object, let voice = value.object["voice"]?.object
        else { throw ProjectError.invalid("\(url.lastPathComponent) is not a take voice speak kept") }
        return (VoiceTakeFile(url: url, generatedBy: generatedBy, provenance: value.object["provenance"] ?? .null), voice)
    }
}

/// Facts of synthesized takes (P0-C4): length, units in the content language's unit and units per second of sound,
/// leading and trailing silence and the pauses inside (under the −70 LUFS gate), and the file. Each take's rate is
/// kept per voice (`VoiceRateStore`) so `speech.rate` and `capabilities.get --voices` can report it.
extension ProjectDocument {
    struct TakeFacts {
        let units: Int
        let leading: Double?
        let trailing: Double?
        let pauses: [JSONValue]

        func rate(seconds: Double) -> Double {
            let sounding = seconds - (leading ?? 0) - (trailing ?? 0)
            return sounding > 0 ? Double(units) / sounding : 0
        }
    }

    func takeFacts(_ take: GeneratedVoiceTake, text: String, unit: SpeechUnits.Unit) async -> TakeFacts {
        let units = SpeechUnits.count(text, unit: unit)
        guard let measured = try? await plugins.running("audio.loudness", {
            try await plugins.service.analyzeLoudness(
                mediaURL: take.asset.url, bands: false, curve: true,
                preferredProvider: project.preferredProvider(for: "audio.loudness"),
                projectRoot: fileURL?.deletingLastPathComponent())
        }), let curve = Self.curve(measured.measurement), let marks = MixMeasure.landmarks(curve)
        else { return TakeFacts(units: units, leading: nil, trailing: nil, pauses: []) }
        let onset = marks["onset"] ?? 0, tail = min(take.durationSeconds, marks["tail"] ?? take.durationSeconds)
        let pauses = (MixMeasure.silences(curve).array).filter { pause in
            let start = pause.object["start"]?.double ?? 0, end = pause.object["end"]?.double ?? 0
            return start > onset && end < tail
        }
        return TakeFacts(units: units, leading: onset, trailing: max(0, take.durationSeconds - tail), pauses: pauses)
    }

    /// The voice a take came from: its provider and the plugin's `voice` option.
    func voiceKey(_ take: GeneratedVoiceTake) -> String {
        let provenance = take.asset.provenance
        let plugin = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent()).plugins
            .first { $0.id == provenance.pluginID }
        let voice = plugin.flatMap { pluginOptionValues($0)["voice"]?.string } ?? "default"
        return provenance.providerID + "/" + voice
    }

    func takesJSON(_ takes: [GeneratedVoiceTake], facts: [TakeFacts], unit: SpeechUnits.Unit) -> [JSONValue] {
        let root = fileURL?.deletingLastPathComponent()
        let round = { (value: Double) in JSONValue.number((value * 100).rounded() / 100) }
        return zip(takes, facts).enumerated().map { index, pair in
            let (take, fact) = pair
            return .object([
                "index": .integer(index + 1), "path": .string(take.asset.url.path),
                "projectPath": root.map { .string(MediaPathResolver.projectPath(for: take.asset.url, projectRoot: $0)) } ?? .null,
                "seconds": round(take.durationSeconds), "units": .integer(fact.units), "unit": .string(unit.rawValue),
                "unitsPerSecond": round(fact.rate(seconds: take.durationSeconds)),
                "leadingSilence": fact.leading.map(round) ?? .null, "trailingSilence": fact.trailing.map(round) ?? .null,
                "pauses": .array(fact.pauses), "score": take.score.map(JSONValue.number) ?? .null,
            ])
        }
    }

    func measureTakes(_ takes: [GeneratedVoiceTake], text: String) async -> (SpeechUnits.Unit, [TakeFacts]) {
        let unit = SpeechUnits.unit(for: contentLanguage)
        var facts: [TakeFacts] = []
        for take in takes {
            let fact = await takeFacts(take, text: text, unit: unit)
            facts.append(fact)
            VoiceRateStore.shared.record(
                voice: voiceKey(take), language: contentLanguage, unit: unit.rawValue,
                rate: fact.rate(seconds: take.durationSeconds))
        }
        return (unit, facts)
    }

    /// Puts a new take into an existing voiceover item (P0-C6): same item and start, new media and length, its voice
    /// facts updated. Captions made from the old take are timed again from the new one (`captions.align` on the
    /// voice text) in a second edit. Returns the revisions.
    func replaceVoiceTake(
        _ take: VoiceTakeFile, item: Item, voice: [String: JSONValue], author: Author
    ) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent(), let oldMedia = item.mediaID else {
            throw ProjectError.invalid("Item \(item.id) plays no media")
        }
        let duration = try await AVURLAsset(url: take.url).load(.duration).seconds
        let frames = Int((duration * project.fps.value).rounded(.down))
        guard frames > 0 else { throw ProjectError.invalid("Voice plugin output is not a valid audio file") }
        let mediaID = UUID().uuidString
        let media = Media(fields: [
            "id": .string(mediaID), "path": .string(Self.relativePath(take.url, root: root)), "kind": .string("audio"),
            "fps": project.fps.json, "frames": .integer(frames), "generatedBy": .object(take.generatedBy),
            "provenance": take.provenance,
        ])
        var operations: [EditOperation] = [.addMedia(media), .setSource(item: item.id, media: mediaID, sourceIn: 0, reversed: nil)]
        if item.speed != 1 { operations.append(.setSpeed(item: item.id, speed: 1, keepDuration: true)) }
        operations += [
            .trim(item: item.id, edge: .end, toFrame: item.at + frames, ripple: false),
            .setProperties(item: item.id, patch: ["voice": .object(voice)]),
        ]
        let revision = try commit(.group(label: "Replace voiceover take", author: author, ops: operations),
                                  label: "Replace voiceover take", author: author)
        var result: [String: JSONValue] = ["rev": .integer(revision), "item": .string(item.id), "media": .string(mediaID)]
        let old = project.tracks.filter { $0.role == TrackRole.captions }.flatMap(\.items)
            .filter { $0["captionMedia"]?.string == oldMedia }
        guard !old.isEmpty, let text = voice["text"]?.string else { return .object(result) }
        let heard = try await heardWords(of: mediaID, item: nil, provider: nil)
        let aligned = TextAlignment.cues(script: text, heard: heard)
        let deletes = old.map { EditOperation.delete(item: $0.id, ripple: false) }
        let cleared = try project.applying(.group(label: "Clear captions", author: author, ops: deletes)).project
        let place = try cleared.importingCues(
            aligned.cues, provenance: ["aligned": .string("voice")], media: mediaID, words: aligned.words)
        result["captionsRev"] = .integer(try commit(
            .group(label: "Align captions to the new take", author: author, ops: deletes + [place]),
            label: "Align captions to the new take", author: author))
        result["captions"] = .integer(aligned.cues.count)
        result["captionScore"] = .number((aligned.alignment.similarity * 1_000).rounded() / 1_000)
        return .object(result)
    }

    /// The voice facts an item keeps: text, language, its hash, provider and voice.
    func voiceFacts(_ take: GeneratedVoiceTake, text: String) -> [String: JSONValue] {
        [
            "text": .string(text), "language": .string(contentLanguage), "textHash": .string(SourceHash.text(text)),
            "provider": .string(take.asset.provenance.providerID), "voice": .string(voiceKey(take)),
        ]
    }

    /// What `voice.speak` was asked for.
    struct SpeakRequest {
        var text: String?
        var count: Int
        var provider: String?
        var cloneConsent: Bool
        var choose: Int?
        var frame: Int?
        var replace: String?
    }

    /// `voice.speak`: generates and measures takes. Without `choose` and `replace` every take file is kept with its
    /// sidecar for `voice.place`; with them take `choose` (default 1) goes in at `frame` or into `replace`, and the
    /// rest are removed.
    func speak(_ request: SpeakRequest, author: Author) async throws -> JSONValue {
        let (count, provider, cloneConsent, choose, frame) = (
            request.count, request.provider, request.cloneConsent, request.choose, request.frame)
        let target = try request.replace.map { try item($0) }
        guard let text = request.text ?? target?["voice"]?.object["text"]?.string else {
            throw ProjectError.invalid("Give the text to say (the item has no voice text)")
        }
        if let choose, choose > count { throw RPCFailure(-32602, "choose must be 1–\(count)") }
        let takes = try await generateVoiceTakes(text: text, count: count, provider: provider, cloneConsent: cloneConsent)
        guard !takes.isEmpty else { throw ProjectError.invalid("Voice provider returned no takes") }
        let (unit, facts) = await measureTakes(takes, text: text)
        let listed = takesJSON(takes, facts: facts, unit: unit)
        guard choose != nil || target != nil else {
            for take in takes {
                let voice = voiceFacts(take, text: text)
                try VoiceTakeFile(take.asset, voice: voice).write(voice: voice)
            }
            return .object(["takes": .array(listed)])
        }
        let index = min(takes.count, choose ?? 1) - 1
        let chosen = takes[index], voice = voiceFacts(chosen, text: text)
        let file = VoiceTakeFile(chosen.asset, voice: voice)
        var result: [String: JSONValue] = ["chosen": .integer(index + 1), "voice": voice["voice"] ?? .null, "takes": .array(listed)]
        do {
            if let target {
                result["replaced"] = try await replaceVoiceTake(file, item: target, voice: voice, author: author)
                result["item"] = .string(target.id)
            } else {
                result["item"] = .string(try await insertVoiceTake(file, at: frame, voice: voice, author: author))
            }
        } catch {
            CapabilityService.discardVoiceTakes(takes)
            throw error
        }
        CapabilityService.discardVoiceTakes(takes, keeping: chosen.asset.url)
        result["rev"] = .integer(project.revision)
        return .object(result)
    }

    /// `voice.place`: a take `voice.speak` kept, inserted at `frame` or put into `replace`.
    func placeVoiceTake(_ path: String, frame: Int?, replace: String?, author: Author) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw ProjectError.invalid("Open a saved project first") }
        let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL
        let generated = root.appendingPathComponent("voiceover/generated", isDirectory: true).standardizedFileURL.path + "/"
        guard url.path.hasPrefix(generated) else { throw ProjectError.invalid("A take is a file voice speak kept in voiceover/generated") }
        let (take, voice) = try VoiceTakeFile.read(url)
        if let replace {
            var result = try await replaceVoiceTake(take, item: try item(replace), voice: voice, author: author).object
            result["rev"] = .integer(project.revision)
            return .object(result)
        }
        let id = try await insertVoiceTake(take, at: frame, voice: voice, author: author)
        try? FileManager.default.removeItem(at: take.sidecar)
        return .object(["rev": .integer(project.revision), "item": .string(id)])
    }
}

extension ProjectDocument {
    func registerVoiceTakeCommands() {
        handleAuthored("voice.speak") { document, arguments, author in
            let text = arguments.optionalString("text")
            let replace = arguments.optionalString("replace")
            guard text != nil || replace != nil else { throw RPCFailure(-32602, "Give the text, or replace an item") }
            let count = try arguments.int("takes")
            let (frame, choose) = (arguments.optionalInt("atFrame"), arguments.optionalInt("choose"))
            let provider = arguments.optionalString("provider")
            let consent = arguments.bool("cloneConsent")
            if let choose, choose > count { throw RPCFailure(-32602, "choose must be 1–\(count)") }
            let work: @MainActor (ProjectDocument) async throws -> JSONValue = { document in
                try await document.speak(
                    SpeakRequest(
                        text: text, count: count, provider: provider, cloneConsent: consent, choose: choose, frame: frame,
                        replace: replace), author: author)
            }
            return try await document.startCapabilityJob("voice.speak", author: author, arguments: arguments, work: work)
        }
        handleAuthored("voice.place") { document, arguments, author in
            do {
                return try await document.placeVoiceTake(
                    try arguments.string("take"), frame: arguments.optionalInt("atFrame"),
                    replace: arguments.optionalString("replace"), author: author)
            } catch let error as ProjectError {
                throw RPCFailure.invalid(error)
            }
        }
    }

    /// The language subtag of a BCP 47 tag, lowercased (`en-US` → `en`); empty for an empty tag.
    static func baseLanguage(_ tag: String) -> String {
        String(tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    /// `capabilities.get --voices` (P0-C7): every voice of the installed `voice.synthesize` providers with its facts, whether the
    /// provider clones, the voice each plugin is set to, the rate measured on its takes and, when the
    /// project has a content language, whether the voice speaks it.
    func voiceList() -> JSONValue {
        let catalog = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        let rates = VoiceRateStore.shared.summary().array
        let content = Self.baseLanguage(contentLanguage)
        var rows: [JSONValue] = []
        for plugin in catalog.plugins {
            for provider in (plugin.manifest.providers ?? []) where provider.capability == "voice.synthesize" {
                let current = pluginOptionValues(plugin)["voice"]?.string
                rows.append(.object([
                    "plugin": .string(plugin.id), "provider": .string(provider.id), "name": .string(provider.name),
                    "availability": .string(plugins.currentAvailability(plugin).name),
                    "clones": .bool(provider.clones ?? false), "current": current.map(JSONValue.string) ?? .null,
                    "voices": .array((provider.voices ?? []).map { voice in
                        let key = provider.id + "/" + voice.id
                        var row: [String: JSONValue] = [
                            "id": .string(voice.id), "language": .string(voice.language),
                            "region": voice.region.map(JSONValue.string) ?? .null,
                            "style": voice.style.map(JSONValue.string) ?? .null,
                            "gender": voice.gender.map(JSONValue.string) ?? .null,
                            "supportsRate": voice.supportsRate.map(JSONValue.bool) ?? .null,
                        ]
                        if !content.isEmpty {
                            row["speaksContentLanguage"] = .bool(Self.baseLanguage(voice.language) == content)
                        }
                        row["measuredRate"] = .array(rates.filter { $0.object["voice"]?.string == key })
                        return .object(row)
                    }),
                ]))
            }
        }
        return .object(["providers": .array(rows)])
    }
}
