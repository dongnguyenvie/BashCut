import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// Voiceover lines in `plan.cut`: the take each line plays (a path, or the kept take of the same text that said it
/// best), as media the build can add, with the words heard in it for captions and graphic timing.
extension ProjectDocument {
    /// Kept takes (`voiceover/generated/*.json` sidecars) whose voice text is `text`, best checked first, then newest.
    func keptTakes(saying text: String, root: URL) -> [(url: URL, sidecar: JSONValue)] {
        // Takes land in one folder per request under voiceover/generated.
        let folder = root.appendingPathComponent("voiceover/generated", isDirectory: true)
        let files = (FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])?.allObjects as? [URL]) ?? []
        let wanted = Self.normalizedLine(text)
        var found: [(url: URL, sidecar: JSONValue, similarity: Double, date: Date)] = []
        for sidecar in files where sidecar.pathExtension == "json" {
            let take = sidecar.deletingPathExtension()
            guard FileManager.default.fileExists(atPath: take.path),
                let data = try? Data(contentsOf: sidecar), let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                let said = value.object["voice"]?.object["text"]?.string, Self.normalizedLine(said) == wanted
            else { continue }
            let date = (try? sidecar.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            found.append((take, value, value.object["check"]?.object["similarity"]?.double ?? -1, date))
        }
        return found.sorted { $0.similarity == $1.similarity ? $0.date > $1.date : $0.similarity > $1.similarity }
            .map { ($0.url, $0.sidecar) }
    }

    static func normalizedLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The words of a file's stored transcript (made by `voice.lines`, `voice.check` or `media.transcribe`).
    func storedWords(_ url: URL, root: URL) -> [CaptionWords.Timed] {
        guard let key = try? SourceTranscript.cacheKey(for: url),
            let record = ProjectCache.record(SourceTranscript.self, .transcripts, key: key, projectRoot: root),
            record.version == SourceTranscript.version, record.key == key
        else { return [] }
        return record.words.filter { $0.event == nil }
    }

    /// Each line's take: the given path, else the best kept take of its text; nil entries are reported by plan check.
    func planLineTakes(_ spec: PlanCut.Spec) async -> [String: PlanCut.LineTake] {
        guard !spec.voiceover.isEmpty, let root = fileURL?.deletingLastPathComponent() else { return [:] }
        var takes: [String: PlanCut.LineTake] = [:]
        for line in spec.voiceover {
            let candidates: [(url: URL, sidecar: JSONValue)]
            if let path = line.take {
                let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL
                let sidecar = (try? Data(contentsOf: url.appendingPathExtension("json")))
                    .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
                candidates = FileManager.default.fileExists(atPath: url.path) ? [(url, sidecar)] : []
            } else {
                candidates = keptTakes(saying: line.text, root: root)
            }
            guard let (url, sidecar) = candidates.first, let take = await lineTake(url, sidecar: sidecar, root: root)
            else { continue }
            takes[line.id] = take
        }
        return takes
    }

    /// The take as media (the project's own when it already plays that file), its voice facts and heard words.
    func lineTake(_ url: URL, sidecar: JSONValue, root: URL) async -> PlanCut.LineTake? {
        let path = Self.relativePath(url, root: root)
        let voice = sidecar.object["voice"]?.object ?? [:]
        var facts: [String: JSONValue] = [:]
        if let check = sidecar.object["check"]?.object {
            facts["similarity"] = check["similarity"] ?? .null
            if let unmatched = check["unmatched"], unmatched != .array([]) { facts["unmatched"] = unmatched }
        }
        let words = storedWords(url, root: root)
        if words.isEmpty { facts["words"] = .bool(false) }
        if let media = project.media.first(where: { $0.fields["path"]?.string == path }) {
            return PlanCut.LineTake(media: media, voice: voice, words: words, facts: facts)
        }
        guard let duration = try? await AVURLAsset(url: url).load(.duration).seconds, duration > 0 else { return nil }
        let frames = Int((duration * project.fps.value).rounded(.down))
        guard frames > 0 else { return nil }
        var fields: [String: JSONValue] = [
            "id": .string(UUID().uuidString), "path": .string(path), "kind": .string("audio"), "fps": project.fps.json,
            "frames": .integer(frames),
        ]
        if let generatedBy = sidecar.object["generatedBy"] { fields["generatedBy"] = generatedBy }
        if let provenance = sidecar.object["provenance"], provenance != .null { fields["provenance"] = provenance }
        return PlanCut.LineTake(media: Media(fields: fields), voice: voice, words: words, facts: facts)
    }

    /// Per graphic, the voiceover words heard during it, in seconds from its start (`plan check --words`), so a
    /// graphic's motion can land on them.
    static func graphicWords(
        _ spec: PlanCut.Spec, takes: [String: PlanCut.LineTake], placements: [PlanCut.Placement], fps: Double
    ) -> [String: JSONValue] {
        var timed: [(text: String, at: Double, end: Double)] = []
        for line in spec.voiceover {
            guard let take = takes[line.id], let placed = placements.first(where: { $0.id == line.id }) else { continue }
            let start = Double(placed.at) / fps, end = Double(placed.end) / fps
            let aligned = TextAlignment.cues(script: line.text, heard: take.words).words
            timed += aligned.map { (text: $0.text, at: start + $0.start, end: start + $0.end) }.filter { $0.at < end }
        }
        var rows: [String: JSONValue] = [:]
        for graphic in spec.graphics {
            guard let placed = placements.first(where: { $0.id == graphic.id }) else { continue }
            let start = Double(placed.at) / fps, end = Double(placed.asked.map { placed.at + $0 } ?? placed.end) / fps
            rows[graphic.id] = .array(timed.filter { $0.end > start && $0.at < end }.map {
                .object(["text": .string($0.text), "at": .number(((max(0, $0.at - start)) * 100).rounded() / 100)])
            })
        }
        return rows
    }
}

/// `voice.lines`: every line voiced, kept and checked in one job.
extension ProjectDocument {
    struct VoiceLinesRequest {
        var lines: [(id: String, text: String)]
        var takes: Int
        var minimum: Double?
        var retries: Int
        var force: Bool
        var provider: String?
        var cloneConsent: Bool
    }

    func registerVoiceLineCommands() {
        handleAuthored("voice.lines") { document, arguments, author in
            let request = try document.voiceLinesRequest(arguments)
            return try await document.startCapabilityJob("voice.lines", author: author, arguments: arguments) { document in
                try await document.voiceLines(request)
            }
        }
    }

    func voiceLinesRequest(_ arguments: CommandArguments) throws -> VoiceLinesRequest {
        let source = arguments["lines"].flatMap { $0 == .null ? nil : $0 } ?? project["plan"]?.object["cut"]?.object["voiceover"]
        guard case .array(let rows)? = source, !rows.isEmpty else {
            throw RPCFailure(-32602, "No lines: give lines [{id, text}] or set plan.cut.voiceover")
        }
        var lines: [(id: String, text: String)] = []
        for (index, row) in rows.enumerated() {
            let text = (row.string ?? row.object["text"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RPCFailure(-32602, "Line \(index + 1) has no text") }
            lines.append((row.object["id"]?.string ?? "l\(index + 1)", text))
        }
        if let only = arguments.optionalString("only") {
            let wanted = Set(only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            let unknown = wanted.subtracting(lines.map(\.id))
            guard unknown.isEmpty else { throw RPCFailure(-32602, "No line \(unknown.sorted().joined(separator: ", "))") }
            lines = lines.filter { wanted.contains($0.id) }
        }
        return VoiceLinesRequest(
            lines: lines, takes: try arguments.int("takes"), minimum: arguments.optionalDouble("minSimilarity"),
            retries: try arguments.int("retries"), force: arguments.bool("force"), provider: arguments.optionalString("provider"),
            cloneConsent: arguments.bool("cloneConsent"))
    }

    func voiceLines(_ request: VoiceLinesRequest) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        var rows: [JSONValue] = []
        for line in request.lines {
            try Task.checkCancellation()
            var row: [String: JSONValue] = ["id": .string(line.id)]
            let kept = keptTakes(saying: line.text, root: root)
            if !request.force, let best = kept.first, Self.passes(best.sidecar, minimum: request.minimum) {
                row["status"] = .string("kept")
                row["best"] = Self.bestJSON(best.url, sidecar: best.sidecar, root: root)
                rows.append(.object(row))
                continue
            }
            var made = 0
            do {
                for _ in 0...request.retries {
                    made += try await voiceLine(line.text, request: request, root: root)
                    if let best = keptTakes(saying: line.text, root: root).first, Self.passes(best.sidecar, minimum: request.minimum) {
                        break
                    }
                }
                row["status"] = .string("made")
            } catch let error where !JobCenter.isCancellation(error) {
                row["status"] = .string("failed")
                row["error"] = .string(error.localizedDescription)
            }
            row["takes"] = .integer(made)
            if let best = keptTakes(saying: line.text, root: root).first {
                row["best"] = Self.bestJSON(best.url, sidecar: best.sidecar, root: root)
                if let unmatched = best.sidecar.object["check"]?.object["unmatched"], unmatched != .array([]) {
                    row["unmatched"] = unmatched
                }
                if let minimum = request.minimum { row["passed"] = .bool(Self.passes(best.sidecar, minimum: minimum)) }
            }
            rows.append(.object(row))
        }
        return .object(["lines": .array(rows)])
    }

    /// Synthesizes, keeps and checks one try of a line; returns how many takes were made.
    func voiceLine(_ text: String, request: VoiceLinesRequest, root: URL) async throws -> Int {
        let takes = try await generateVoiceTakes(
            text: text, count: request.takes, provider: request.provider, cloneConsent: request.cloneConsent)
        let (unit, facts) = await measureTakes(takes, text: text)
        let listed = takesJSON(takes, facts: facts, unit: unit)
        for (take, measured) in zip(takes, listed) {
            let voice = voiceFacts(take, text: text)
            let file = VoiceTakeFile(take.asset, voice: voice)
            try file.write(voice: voice)
            var check: [String: JSONValue] = [
                "seconds": measured.object["seconds"] ?? .null, "unitsPerSecond": measured.object["unitsPerSecond"] ?? .null,
            ]
            if let heard = try? await transcribeFile(take.asset.url, root: root) {
                let result = TextAlignment.align(text, to: heard)
                check["similarity"] = .number((result.similarity * 1_000).rounded() / 1_000)
                check["unmatched"] = TextAlignment.unmatchedJSON(result)
            }
            try Self.addCheck(check, to: file.sidecar)
        }
        return takes.count
    }

    /// Transcribes a file outside the project's media and keeps the transcript by its content, so a take placed
    /// later finds it like any media's.
    func transcribeFile(_ url: URL, root: URL) async throws -> [CaptionWords.Timed] {
        let key = try SourceTranscript.cacheKey(for: url)
        let generated = try await plugins.running("captions.transcribe") {
            try await plugins.service.transcribe(
                mediaURL: url, language: contentLanguage,
                preferredProvider: project.preferredProvider(for: "captions.transcribe"), projectRoot: root,
                outputRoot: root.appendingPathComponent("subtitles/generated", isDirectory: true))
        }
        let transcript = SourceTranscript(
            key: key, language: contentLanguage, provider: generated.provenance.json,
            transcribedAt: ISO8601DateFormatter().string(from: Date()), phrases: try SubRip.cues(generated.text),
            words: generated.words)
        try ProjectCache.store(transcript, .transcripts, key: key, projectRoot: root)
        return transcript.words.filter { $0.event == nil }
    }

    static func addCheck(_ check: [String: JSONValue], to sidecar: URL) throws {
        let data = try Data(contentsOf: sidecar)
        guard case .object(var fields) = try JSONDecoder().decode(JSONValue.self, from: data) else { return }
        fields["check"] = .object(check)
        try JSONEncoder().encode(JSONValue.object(fields)).write(to: sidecar, options: .atomic)
    }

    static func passes(_ sidecar: JSONValue, minimum: Double?) -> Bool {
        guard let similarity = sidecar.object["check"]?.object["similarity"]?.double else { return minimum == nil }
        return similarity >= (minimum ?? 0)
    }

    static func bestJSON(_ url: URL, sidecar: JSONValue, root: URL) -> JSONValue {
        let check = sidecar.object["check"]?.object ?? [:]
        return .object([
            "projectPath": .string(relativePath(url, root: root)), "similarity": check["similarity"] ?? .null,
            "seconds": check["seconds"] ?? .null, "unitsPerSecond": check["unitsPerSecond"] ?? .null,
        ])
    }
}
