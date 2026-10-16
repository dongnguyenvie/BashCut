import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// What was said in each source media, in its own seconds (P0-A2): `media.transcribe` runs `captions.transcribe`
/// once per file and keeps the result by file content; `media.transcript` reads it; `captions.generate` places
/// captions from it; `transcript.words --heard` maps it through the clips.
extension ProjectDocument {
    nonisolated static func transcriptKey(_ url: URL) async throws -> String {
        try SourceTranscript.cacheKey(for: url)
    }

    /// The stored transcript of `mediaID` for its file as it is now, or nil, with its words kept out of the silences
    /// `media.analyze` measured (B4), so plan edges, captions and the timeline's words use one set of word times.
    func storedTranscript(_ mediaID: String) async throws -> SourceTranscript? {
        try await clampedTranscript(mediaID)?.transcript
    }

    /// The stored transcript with its words kept out of measured silences, and how many words moved.
    func clampedTranscript(_ mediaID: String) async throws -> (transcript: SourceTranscript, moved: Int)? {
        guard let raw = try await rawTranscript(mediaID) else { return nil }
        guard let sound = (try? storedAnalysis(mediaID))?.record?.sound else { return (raw, 0) }
        return raw.clamped(to: sound)
    }

    /// The stored transcript with the word times as the recognizer gave them.
    func rawTranscript(_ mediaID: String) async throws -> SourceTranscript? {
        let source = try analysisSource(mediaID)
        return try await Self.rawTranscript(source.media, url: source.url, root: source.root, workspace: settings.workspace)
    }

    /// The stored transcript of `media` (its file at `url`), read off the main actor.
    nonisolated static func rawTranscript(_ media: Media, url: URL, root: URL, workspace: URL?) async throws
        -> SourceTranscript?
    {
        var urls = [url]
        // A converted media (AV1, VP9 → H.264) keeps the sound and timing of its original: a transcript made from the
        // original before the conversion finished still holds.
        if let original = media.fields["originalPath"]?.string,
            let originalURL = try? MediaPathResolver.resolve(original, projectRoot: root, workspaceRoot: workspace),
            originalURL != url, FileManager.default.fileExists(atPath: originalURL.path)
        {
            urls.append(originalURL)
        }
        for url in urls {
            let key = try SourceTranscript.cacheKey(for: url)
            if let record = ProjectCache.record(SourceTranscript.self, .transcripts, key: key, projectRoot: root),
                record.version == SourceTranscript.version, record.key == key
            {
                return record
            }
        }
        return nil
    }

    /// The stored transcript when it is in the content language (any, while the project has none: it then holds the
    /// language heard) and, when `provider` is given, made by it (the provider or its plugin).
    func reusableTranscript(_ mediaID: String, provider: String?) async throws -> SourceTranscript? {
        guard let stored = try await storedTranscript(mediaID), contentLanguage.isEmpty || stored.language == contentLanguage
        else { return nil }
        if let provider, ![stored.provider["provider"], stored.provider["plugin"]].contains(.string(provider)) {
            return nil
        }
        return stored
    }

    /// Transcribes the whole of `mediaID` and keeps the result.
    func transcribeSource(_ mediaID: String, provider: String?) async throws -> SourceTranscript {
        let source = try analysisSource(mediaID)
        let key = try await Self.transcriptKey(source.url)
        let generated = try await transcribe(mediaID, provider: provider)
        // A project without a content language keeps the language the provider heard, so it can be set from it.
        let transcript = SourceTranscript(
            key: key, language: contentLanguage.isEmpty ? generated.language ?? "" : contentLanguage,
            provider: generated.provenance.json,
            transcribedAt: ISO8601DateFormatter().string(from: Date()), phrases: try SubRip.cues(generated.text),
            words: generated.words)
        try ProjectCache.store(transcript, .transcripts, key: key, projectRoot: source.root)
        return transcript
    }

    /// Transcribes the listed media (every video and audio media when nil) one after another, reusing stored
    /// transcripts unless `force`.
    func startMediaTranscribe(
        mediaID: String?, provider: String?, force: Bool, author: Author, arguments: CommandArguments? = nil
    ) async throws -> JSONValue {
        let selected = try mediaID.map { [try analysisSource($0).media] } ?? project.media.filter { !$0.isImage }
        return try await startCapabilityJob("media.transcribe", author: author, arguments: arguments) { document in
            var results: [JSONValue] = []
            for media in selected {
                try Task.checkCancellation()
                var row: [String: JSONValue] = ["media": .string(media.id)]
                do {
                    if !force, let stored = try await document.reusableTranscript(media.id, provider: provider) {
                        row["status"] = .string("reused")
                        row["overview"] = stored.overviewJSON
                    } else {
                        row["overview"] = try await document.transcribeSource(media.id, provider: provider).overviewJSON
                        row["status"] = .string("transcribed")
                    }
                } catch let error where !JobCenter.isCancellation(error) && selected.count > 1 {
                    // One file without speech or missing does not stop the others.
                    row["status"] = .string("failed")
                    row["error"] = .string(error.localizedDescription)
                }
                results.append(.object(row))
            }
            return .object(["media": .array(results)])
        }
    }

    func registerSourceTranscriptCommands() {
        handle("media.resolve-range") { document, arguments, _ in try await document.resolveRange(arguments) }
        handle("captions.find") { document, arguments, _ in await document.findSpoken(try arguments.string("text")) }
        handleAuthored("media.transcribe") { document, arguments, author in
            try await document.startMediaTranscribe(
                mediaID: arguments.optionalString("media"), provider: arguments.optionalString("provider"),
                force: arguments.bool("force"), author: author, arguments: arguments)
        }
        handle("media.transcript") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            guard let (transcript, moved) = try await document.clampedTranscript(mediaID) else {
                throw RPCFailure(-32602, "Media \(mediaID) has no transcript: run media transcribe --media \(mediaID) first")
            }
            let format = SourceTranscript.Format(rawValue: arguments.optionalString("as") ?? "phrases") ?? .phrases
            if let ranges = arguments.optionalString("ranges") {
                return try Self.transcriptWindows(transcript, media: mediaID, format: format, ranges: ranges)
            }
            let from = arguments.optionalDouble("from") ?? 0, to = arguments.optionalDouble("to")
            if let to, to <= from { throw RPCFailure(-32602, "to must be after from") }
            guard case .object(var result) = transcript.json(format, from: from, to: to) else {
                return transcript.json(format, from: from, to: to)
            }
            result["media"] = .string(mediaID)
            result["wordsKeptOutOfSilences"] = .integer(moved)
            if format == .phrases {
                // words and phrases above are counts (B8).
                result["wordListHint"] = .string("words and phrases are counts; --as words (or json) lists every word with its times")
            }
            return .object(result)
        }
    }

    /// `media.transcript --ranges A:B,C:D`: several windows of one transcript in one call.
    static func transcriptWindows(
        _ transcript: SourceTranscript, media: String, format: SourceTranscript.Format, ranges: String
    ) throws -> JSONValue {
        let windows = try ranges.split(separator: ",").map { part -> (Double, Double) in
            let bounds = part.split(whereSeparator: { $0 == ":" || $0 == "-" || $0 == "–" })
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard bounds.count == 2, bounds[0] >= 0, bounds[1] > bounds[0] else {
                throw RPCFailure(-32602, "ranges must be A:B,C:D with A < B in source seconds; got \(part)")
            }
            return (bounds[0], bounds[1])
        }
        guard !windows.isEmpty, windows.count <= 50 else { throw RPCFailure(-32602, "ranges takes 1 to 50 windows") }
        let label = { (window: (Double, Double)) in String(format: "%g–%g s", window.0, window.1) }
        if format == .text {
            return .string(windows.map { window in
                "== \(label(window))\n" + (transcript.json(.text, from: window.0, to: window.1).string ?? "")
            }.joined(separator: "\n"))
        }
        return .object([
            "media": .string(media),
            "ranges": .array(windows.map { transcript.json(format, from: $0.0, to: $0.1) }),
        ])
    }

    /// `transcript.words --heard`: stored transcripts of the media the timeline plays, mapped through the clips.
    func heardWords(from: Int, to: Int?, media: String?) async -> JSONValue {
        var transcripts: [String: SourceTranscript] = [:]
        let used = Set(project.tracks.flatMap(\.items).compactMap(\.mediaID))
        for mediaID in used.sorted() where media == nil || mediaID == media {
            if let stored = try? await storedTranscript(mediaID) { transcripts[mediaID] = stored }
        }
        guard case .object(var result) = TimelineTranscript.heardWordsJSON(
            project, transcripts: transcripts, from: from, to: to, media: media)
        else { return .null }
        result["transcribed"] = .array(transcripts.keys.sorted().map(JSONValue.string))
        result["untranscribed"] = .array(used.subtracting(transcripts.keys).filter { id in
            project.media.first { $0.id == id }.map { !$0.isImage } ?? false
        }.sorted().map(JSONValue.string))
        return .object(result)
    }

    /// `media.list --analysis`: the transcript overview of a media, or transcribed false.
    func mediaTranscriptOverview(_ media: Media) async -> JSONValue {
        guard !media.isImage, let stored = try? await storedTranscript(media.id) else {
            return .object(["transcribed": .bool(false)])
        }
        return stored.overviewJSON
    }

    /// `media.resolve-range` (P1-D7): a quote, word indices or rough times in the media's stored transcript → word
    /// edges with flags and boundaries. Several equal matches: the first, with the others listed in order.
    func resolveRange(_ arguments: CommandArguments) async throws -> JSONValue {
        let mediaID = try arguments.string("media")
        guard let media = project.media.first(where: { $0.id == mediaID }) else { throw RPCFailure(-32602, "Unknown media \(mediaID)") }
        guard let transcript = try await storedTranscript(mediaID) else {
            throw RPCFailure(-32602, "\(mediaID) has no transcript yet: media transcribe first")
        }
        let words = transcript.words.filter { $0.event == nil }
        do {
            if let quote = arguments.optionalString("quote") {
                let found = QuoteRange.find(quote, in: words)
                guard let best = found.first else { throw RPCFailure(-32602, "The quote was not found in \(mediaID)'s transcript") }
                var row = try QuoteRange.json(
                    transcript, media: media, first: best.first, last: best.last, matches: found.count).object
                row["matched"] = .number(Double(best.matched) / Double(max(1, best.last - best.first + 1)))
                row["alternatives"] = .array(found.dropFirst().map { match in
                    .object(["first": .integer(match.first), "last": .integer(match.last), "from": .number(words[match.first].start)])
                })
                return .object(row)
            }
            if let span = arguments.optionalString("words") {
                let parts = span.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2 else { throw RPCFailure(-32602, "words is FIRST-LAST, such as 12-30") }
                return try QuoteRange.json(transcript, media: media, first: parts[0], last: parts[1])
            }
            return try QuoteRange.json(
                transcript, media: media, from: arguments.optionalDouble("from"), to: arguments.optionalDouble("to"))
        } catch let error as ProjectError {
            throw RPCFailure.invalid(error)
        }
    }

    /// `captions.find`: where words are said on the timeline, in order (heard words, else caption words).
    func findSpoken(_ text: String) async -> JSONValue {
        let (spans, source) = await syncWords()
        let timed = spans.map { CaptionWords.Timed(text: $0.text, start: Double($0.at), end: Double($0.end)) }
        let wanted = SpeechUnits.tokens(text).count
        let found = QuoteRange.find(text, in: timed).filter { $0.matched == wanted }
        return .object([
            "wordSource": .string(source),
            "matches": .array(found.map { match in
                .object([
                    "at": .integer(spans[match.first].at), "end": .integer(spans[match.last].end),
                    "text": .string(spans[match.first...match.last].map(\.text).joined(separator: " ")),
                ])
            }),
        ])
    }
}
