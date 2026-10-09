import BashCutAutomation
import BashCutPlugins
import BashCutProject
import Foundation

/// Checking and fitting voiceover, and captions from a script (P0-C5, P0-C6, P0-C9): `voice.check` transcribes a take
/// and diffs it against the text it should say; `voice.fit` changes a voiceover item's speed (pitch kept) to fill a
/// slot within the caller's bounds; `captions.align` makes captions whose text is the script and whose times come
/// from the speech.
extension ProjectDocument {
    /// What was heard in `mediaID` (its stored transcript, or a new one), within `item`'s source range when given.
    func heardWords(of mediaID: String, item: Item?, provider: String?) async throws -> [CaptionWords.Timed] {
        var transcript = try await reusableTranscript(mediaID, provider: provider)
        if transcript == nil { transcript = try await transcribeSource(mediaID, provider: provider) }
        guard let transcript else { return [] }
        guard let item, let media = project.media.first(where: { $0.id == mediaID }) else { return transcript.words }
        let span = project.sourceSpan(of: item, media: media)
        return transcript.words.filter { $0.end > span.lowerBound && $0.start < span.upperBound }
    }

    func item(_ id: String) throws -> Item {
        guard let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }) else {
            throw RPCFailure(-32602, "Unknown item \(id)")
        }
        return item
    }

    func registerVoiceCheckCommands() {
        handleAuthored("voice.check") { document, arguments, author in
            let itemID = arguments.optionalString("item")
            let item = try itemID.map { try document.item($0) }
            guard let mediaID = item?.mediaID ?? arguments.optionalString("media") else {
                throw RPCFailure(-32602, "Give a voiceover item or a media")
            }
            guard let text = arguments.optionalString("text") ?? item?["voice"]?.object["text"]?.string else {
                throw RPCFailure(-32602, "Give the text the take should say")
            }
            let provider = arguments.optionalString("provider")
            let minimum = arguments.optionalDouble("minSimilarity")
            return try await document.startCapabilityJob("voice.check", author: author, arguments: arguments) { document in
                let heard = try await document.heardWords(of: mediaID, item: item, provider: provider)
                let result = TextAlignment.align(text, to: heard)
                var json: [String: JSONValue] = [
                    "media": .string(mediaID), "similarity": .number((result.similarity * 1_000).rounded() / 1_000),
                    "words": .array(result.words.map { word in
                        .object([
                            "text": .string(word.text), "heard": word.heard.map(JSONValue.string) ?? .null,
                            "kind": .string(word.kind), "start": .number((word.start * 1_000).rounded() / 1_000),
                            "end": .number((word.end * 1_000).rounded() / 1_000),
                        ])
                    }),
                    "unmatched": TextAlignment.unmatchedJSON(result),
                    "extra": .array(result.extra.map { .object(["text": .string($0.text), "start": .number($0.start)]) }),
                ]
                if let itemID { json["item"] = .string(itemID) }
                if let minimum { json["passed"] = .bool(result.similarity >= minimum) }
                return .object(json)
            }
        }
        handleAuthored("captions.group") { document, arguments, author in
            try await document.groupCaptions(arguments, author: author)
        }
        handleAuthored("voice.fit") { document, arguments, author in
            try document.fitVoice(arguments, author: author)
        }
        handleAuthored("captions.align") { document, arguments, author in
            let mediaID = try arguments.string("media")
            let script = try arguments.string("text")
            let provider = arguments.optionalString("provider")
            let replace = arguments.bool("replace")
            let aligner = arguments.optionalString("aligner")
            return try await document.startCapabilityJob("captions.align", author: author, arguments: arguments) { document in
                let heard: [CaptionWords.Timed]
                if let aligner {
                    // A captions.align provider times the script's own words; matching them is then exact.
                    let (root, _, url) = try document.capabilityMedia(mediaID)
                    heard = try await document.plugins.running("captions.align") {
                        try await document.plugins.service.alignText(
                            mediaURL: url, text: script, language: document.contentLanguage, preferredProvider: aligner,
                            projectRoot: root)
                    }
                } else {
                    heard = try await document.heardWords(of: mediaID, item: nil, provider: provider)
                }
                let aligned = TextAlignment.cues(script: script, heard: heard)
                guard let first = aligned.cues.first, let last = aligned.cues.last else {
                    throw RPCFailure(-32602, "The text has no words")
                }
                try document.commit(
                    document.project.importingCues(
                        aligned.cues, replace: replace, provenance: ["aligned": .string("script")], media: mediaID,
                        words: aligned.words, range: replace ? first.start...last.end : nil),
                    label: "Align captions to script", author: author)
                return .object([
                    "rev": .integer(document.project.revision), "cues": .integer(aligned.cues.count),
                    "score": .number((aligned.alignment.similarity * 1_000).rounded() / 1_000),
                    "unmatched": TextAlignment.unmatchedJSON(aligned.alignment),
                ])
            }
        }
    }

    /// Changes a voiceover item's speed so it lasts `frames` (or reaches `toFrame`), pitch kept, when the needed
    /// ratio is inside the caller's bounds; otherwise refuses with the ratio it would need.
    func fitVoice(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let item = try item(try arguments.string("item"))
        guard let mediaID = item.mediaID, let media = project.media.first(where: { $0.id == mediaID }) else {
            throw RPCFailure(-32602, "Item \(item.id) plays no media")
        }
        let target: Int
        switch (arguments.optionalInt("frames"), arguments.optionalInt("toFrame")) {
        case (let frames?, nil): target = frames
        case (nil, let end?): target = end - item.at
        default: throw RPCFailure(-32602, "Give frames or toFrame")
        }
        guard target > 0 else { throw RPCFailure(-32602, "The slot must end after the item starts") }
        guard let minimum = arguments.optionalDouble("minRatio"), let maximum = arguments.optionalDouble("maxRatio"),
            minimum <= maximum
        else { throw RPCFailure(-32602, "Give minRatio and maxRatio (speed bounds, min ≤ max)") }
        let span = project.sourceSpan(of: item, media: media)
        let sourceSeconds = span.upperBound - span.lowerBound
        let ratio = sourceSeconds / (Double(target) / project.fps.value)
        let round = { (value: Double) in JSONValue.number((value * 1_000).rounded() / 1_000) }
        guard ratio >= minimum, ratio <= maximum else {
            throw RPCFailure(
                -32602, String(format: "Fitting needs speed %.3f, outside %.2f–%.2f; change the slot or the bounds", ratio,
                               minimum, maximum))
        }
        var operations: [EditOperation] = [.setSpeed(item: item.id, speed: ratio, keepDuration: false)]
        if item["preservePitch"] == .bool(false) {
            operations.append(.setProperties(item: item.id, patch: ["preservePitch": .bool(true)]))
        }
        let revision = try commit(
            .group(label: "Fit voiceover", author: author, ops: operations), label: "Fit voiceover", author: author,
            baseRevision: arguments.int("baseRev"))
        let fitted = (try? self.item(item.id))?.duration ?? target
        return .object([
            "rev": .integer(revision), "item": .string(item.id), "speed": round(ratio),
            "frames": .integer(fitted), "slackFrames": .integer(target - fitted), "pitchKept": .bool(true),
        ])
    }

    /// `captions.group` (P0-C8): captions from the agent's word groups (or the caller's rule) as one undoable edit.
    func groupCaptions(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        let words: [ReviewSync.WordSpan]
        if arguments.optionalString("source") == "heard" {
            words = (await heardWords(from: 0, to: nil, media: nil)).object["words"]?.array.compactMap(Self.span) ?? []
        } else {
            words = TimelineTranscript.wordsJSON(project).object["words"]?.array.compactMap(Self.span) ?? []
        }
        guard !words.isEmpty else { throw RPCFailure(-32602, "No words to group: transcribe or add captions first") }
        let rule = (arguments.optionalInt("maxChars"), arguments.optionalDouble("maxSeconds"), arguments.optionalDouble("breakGapSeconds"))
        var groups: [[Int]]
        switch (arguments["groups"], rule) {
        case (let value?, (nil, nil, nil)):
            groups = try value.array.map { group in
                guard case .array(let indexes) = group, indexes.allSatisfy({ $0.int != nil }) else {
                    throw RPCFailure(-32602, "groups must be arrays of word indices")
                }
                return indexes.compactMap(\.int)
            }
        case (nil, (let chars?, let seconds?, let gap?)):
            let from = arguments.optionalInt("from") ?? 0, to = arguments.optionalInt("to") ?? Int.max
            let inside = words.indices.filter { words[$0].end > from && words[$0].at < to }
            let rule = CaptionGrouping.Rule(maxChars: chars, maxSeconds: seconds, breakGapSeconds: gap)
            groups = CaptionGrouping.groups(inside.map { words[$0] }, rule: rule, fps: project.fps.value)
                .map { $0.map { inside[$0] } }
        default:
            throw RPCFailure(-32602, "Give groups, or all of maxChars, maxSeconds and breakGapSeconds")
        }
        let planned: (operation: EditOperation, cues: [Item])
        do { planned = try CaptionGrouping.operation(project, words: words, groups: groups, author: author) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        let revision = try commit(planned.operation, label: "Group captions", author: author, baseRevision: arguments.int("baseRev"))
        var result = CaptionGrouping.facts(planned.cues, fps: project.fps.value).object
        result["rev"] = .integer(revision)
        return .object(result)
    }

    static func span(_ word: JSONValue) -> ReviewSync.WordSpan? {
        guard let at = word.object["at"]?.int, let end = word.object["end"]?.int else { return nil }
        return ReviewSync.WordSpan(at: at, end: end, text: word.object["text"]?.string ?? "")
    }
}
