import AVFoundation
import BashCutAutomation
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
import Foundation

/// How `voice.speak` picks a take (P0-C4): the take closest to a target rate, a take by number, or the provider's
/// own score (the first take when it gives none). BashCut has no pace formula of its own.
struct VoiceChoice: Sendable {
    let targetRate: Double?
    let index: Int?

    init(targetRate: Double?, index: Int?, count: Int) throws {
        guard targetRate == nil || index == nil else { throw RPCFailure(-32602, "Give targetRate or choose, not both") }
        if let index, !(1...count).contains(index) { throw RPCFailure(-32602, "choose must be 1–\(count)") }
        self.targetRate = targetRate
        self.index = index
    }
}

/// Facts of synthesized takes (P0-C4): length, units in the content language's unit and units per second of sound,
/// leading and trailing silence and the pauses inside (under the −70 LUFS gate), and the file. Each take's rate is
/// kept per voice (`VoiceRateStore`) so `speech.rate` and `voice.voices` can report it.
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

    /// The chosen take's index (0-based) and how it was chosen.
    func choose(_ takes: [GeneratedVoiceTake], facts: [TakeFacts], choice: VoiceChoice) -> (Int, String) {
        if let index = choice.index { return (index - 1, "choose") }
        if let target = choice.targetRate {
            let best = zip(takes, facts).enumerated().min { lhs, rhs in
                abs(lhs.element.1.rate(seconds: lhs.element.0.durationSeconds) - target)
                    < abs(rhs.element.1.rate(seconds: rhs.element.0.durationSeconds) - target)
            }?.offset ?? 0
            return (best, "targetRate")
        }
        guard let best = takes.best, let index = takes.firstIndex(where: { $0.id == best.id }) else { return (0, "first") }
        return (index, best.score == nil ? "first" : "providerScore")
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
        _ asset: GeneratedPluginAsset, item: Item, voice: [String: JSONValue], author: Author
    ) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent(), let oldMedia = item.mediaID else {
            throw ProjectError.invalid("Item \(item.id) plays no media")
        }
        let duration = try await AVURLAsset(url: asset.url).load(.duration).seconds
        let frames = Int((duration * project.fps.value).rounded(.down))
        guard frames > 0 else { throw ProjectError.invalid("Voice plugin output is not a valid audio file") }
        let mediaID = UUID().uuidString
        let media = Media(fields: [
            "id": .string(mediaID), "path": .string(Self.relativePath(asset.url, root: root)), "kind": .string("audio"),
            "fps": project.fps.json, "frames": .integer(frames),
            "generatedBy": .object(Self.voiceProvenance(asset, voice: voice)),
            "provenance": Self.voiceTakeProvenance(asset),
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

    /// What `voice.speak` was asked for.
    struct SpeakRequest {
        var text: String?
        var count: Int
        var frame: Int?
        var provider: String?
        var choice: VoiceChoice
        var replace: String?
        var cloneConsent: Bool
    }

    /// Generates takes, inserts the chosen one (or puts it into `replace`) and removes the rest.
    func speak(_ request: SpeakRequest, author: Author) async throws -> JSONValue {
        let (text, count, frame, provider, choice, cloneConsent) = (
            request.text, request.count, request.frame, request.provider, request.choice, request.cloneConsent)
        let target = try request.replace.map { try item($0) }
        guard let text = text ?? target?["voice"]?.object["text"]?.string else {
            throw ProjectError.invalid("Give the text to say (the item has no voice text)")
        }
        let takes = try await generateVoiceTakes(text: text, count: count, provider: provider, cloneConsent: cloneConsent)
        guard !takes.isEmpty else { throw ProjectError.invalid("Voice provider returned no takes") }
        let (unit, facts) = await measureTakes(takes, text: text)
        let (index, how) = choose(takes, facts: facts, choice: choice)
        let chosen = takes[index]
        let itemID: String
        let voice: [String: JSONValue] = [
            "text": .string(text), "language": .string(contentLanguage), "textHash": .string(SourceHash.text(text)),
            "provider": .string(chosen.asset.provenance.providerID), "voice": .string(voiceKey(chosen)),
        ]
        var replaced: JSONValue = .null
        do {
            if let target {
                replaced = try await replaceVoiceTake(chosen.asset, item: target, voice: voice, author: author)
                itemID = target.id
            } else {
                itemID = try await insertVoiceTake(chosen.asset, at: frame, voice: voice, author: author)
            }
        } catch {
            CapabilityService.discardVoiceTakes(takes)
            throw error
        }
        let listed = takesJSON(takes, facts: facts, unit: unit)
        CapabilityService.discardVoiceTakes(takes, keeping: chosen.asset.url)
        return .object([
            "rev": .integer(project.revision), "item": .string(itemID), "chosen": .integer(index + 1),
            "chosenBy": .string(how), "voice": .string(voiceKey(chosen)), "takes": .array(listed), "replaced": replaced,
        ])
    }

    /// Generates takes and keeps every file (like the Voice panel's take list) without inserting one.
    func generateKeptTakes(text: String, count: Int, provider: String?, cloneConsent: Bool) async throws -> JSONValue {
        let takes = try await generateVoiceTakes(text: text, count: count, provider: provider, cloneConsent: cloneConsent)
        let (unit, facts) = await measureTakes(takes, text: text)
        return .object([
            "best": takes.best.map { .string($0.asset.url.path) } ?? .null,
            "takes": .array(takesJSON(takes, facts: facts, unit: unit)),
        ])
    }
}

extension ProjectDocument {
    func registerVoiceTakeCommands() {
        handleAuthored("voice.speak") { document, arguments, author in
            let text = arguments.optionalString("text")
            let replace = arguments.optionalString("replace")
            guard text != nil || replace != nil else { throw RPCFailure(-32602, "Give the text, or replace an item") }
            let count = try arguments.int("takes")
            let frame = arguments.optionalInt("atFrame")
            let provider = arguments.optionalString("provider")
            let keepTakes = arguments.bool("keepTakes")
            let consent = arguments.bool("cloneConsent")
            let choice = try VoiceChoice(
                targetRate: arguments.optionalDouble("targetRate"), index: arguments.optionalInt("choose"), count: count)
            let work: @MainActor (ProjectDocument) async throws -> JSONValue = { document in
                if keepTakes, let text {
                    return try await document.generateKeptTakes(
                        text: text, count: count, provider: provider, cloneConsent: consent)
                }
                return try await document.speak(
                    SpeakRequest(
                        text: text, count: count, frame: frame, provider: provider, choice: choice, replace: replace,
                        cloneConsent: consent), author: author)
            }
            if arguments.bool("dryRun") { return try await document.capabilityDryRun(work) }
            return try document.startCapabilityJob(
                "voice.speak", author: author, requestID: arguments.optionalString("requestId"), work: work)
        }
        handle("voice.voices") { document, _, _ in document.voiceList() }
    }

    /// `voice.voices` (P0-C7): every voice of the installed `voice.synthesize` providers with its facts, whether the
    /// provider clones, the voice each plugin is set to, and the rate measured on its takes.
    func voiceList() -> JSONValue {
        let catalog = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        let rates = VoiceRateStore.shared.summary().array
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
                        row["measuredRate"] = .array(rates.filter { $0.object["voice"]?.string == key })
                        return .object(row)
                    }),
                ]))
            }
        }
        return .object(["providers": .array(rows)])
    }
}
