import Foundation

/// Captions and spoken words as they sit on the timeline now, as data for the agent (P0-C1): `captions.export
/// --format json|text` and `transcript.words`. Measured facts only (frames, seconds, characters, characters per
/// second, gaps); a skill compares them with the range its genre allows.
///
/// Words come from each caption's `words` (transcribed timings, `timing: transcribed`) or are spread over the caption
/// by word length (`timing: estimated`), like the word-by-word renderer. A caption made from a media
/// (`captionMedia`) maps each word to that media's source seconds through the clip heard at the word now; captions do
/// not move with their clips, so a word whose clip was trimmed away or moved has no source.
public enum TimelineTranscript {
    /// One caption cue: a non-empty text item on a text layer, in SubRip order.
    public struct Cue: Sendable {
        public let index: Int
        public let item: Item
        public let track: Track
    }

    /// Text items on text layers with visible text, ordered by start (then layer order), numbered from 1 like the
    /// SubRip export.
    public static func cues(_ project: Project) -> [Cue] {
        let tracks = project.tracks.filter { $0.kind == "text" }
        let placed: [(item: Item, track: Track)] = tracks.flatMap { track in track.items.map { (item: $0, track: track) } }
            .filter { !$0.item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // A stable sort by start: equal starts keep layer order.
        let order = placed.indices.sorted { placed[$0].item.at == placed[$1].item.at ? $0 < $1 : placed[$0].item.at < placed[$1].item.at }
        return order.enumerated().map { Cue(index: $0.offset + 1, item: placed[$0.element].item, track: placed[$0.element].track) }
    }

    /// The cues with timing, characters, characters per second, the gap since the previous cue and their words.
    public static func captionsJSON(_ project: Project) -> JSONValue {
        let fps = project.fps.value
        let sources = SourceMap(project)
        var previousEnd: Int?
        let cues: [JSONValue] = cues(project).map { cue in
            defer { previousEnd = max(previousEnd ?? cue.item.end, cue.item.end) }
            let item = cue.item
            let text = oneLine(item.text)
            let seconds = Double(item.duration) / fps
            var row: [String: JSONValue] = [
                "index": .integer(cue.index), "item": .string(item.id), "track": .string(cue.track.id),
                "trackRole": .string(cue.track.role), "at": .integer(item.at), "end": .integer(item.end),
                "duration": .integer(item.duration), "atSeconds": .number(rounded(Double(item.at) / fps)),
                "endSeconds": .number(rounded(Double(item.end) / fps)), "seconds": .number(rounded(seconds)),
                "text": .string(item.text), "lines": .integer(lines(item.text).count), "chars": .integer(text.count),
                "cps": .number(seconds > 0 ? rounded(Double(text.count) / seconds) : 0),
                "words": .array(words(of: item, sources: sources).map { $0.json(fps: fps) }),
                "wordTiming": .string(hasTimedWords(item) ? "transcribed" : "estimated"),
            ]
            if let previousEnd { row["gapBefore"] = .integer(item.at - previousEnd) }
            if let media = item["captionMedia"]?.string { row["captionMedia"] = .string(media) }
            if let style = item.wordStyle { row["wordStyle"] = .string(style) }
            return .object(row)
        }
        return .object(["revision": .integer(project.revision), "fps": .number(fps), "cues": .array(cues)])
    }

    /// One line per cue for a cheap read: `#index start–end seconds cps | text`, times as HH:MM:SS.mmm, line breaks
    /// shown as " / ".
    public static func captionsText(_ project: Project) -> String {
        let fps = project.fps.value
        return cues(project).map { cue in
            let item = cue.item
            let seconds = Double(item.duration) / fps
            let text = oneLine(item.text)
            let cps = seconds > 0 ? Double(text.count) / seconds : 0
            return "#\(cue.index) \(clock(Double(item.at) / fps))–\(clock(Double(item.end) / fps)) "
                + String(format: "%.2fs %.1fcps", seconds, cps) + " | "
                + lines(item.text).joined(separator: " / ")
        }.joined(separator: "\n")
    }

    /// Every word on the caption layers in timeline order, with its timeline frames, caption, timing kind, the gap
    /// since the previous word and its source seconds. `from`/`to` keep the words that overlap that frame span.
    public static func wordsJSON(_ project: Project, from: Int = 0, to: Int? = nil, media: String? = nil) -> JSONValue {
        let fps = project.fps.value
        let sources = SourceMap(project)
        let spoken = cues(project).filter { $0.track.role == TrackRole.captions }.filter { media == nil || $0.item["captionMedia"]?.string == media }
        let unsorted: [(cue: Cue, word: Word)] = spoken.flatMap { cue in
            words(of: cue.item, sources: sources).map { (cue: cue, word: $0) }
        }
        let all = unsorted.sorted { $0.word.at == $1.word.at ? $0.cue.index < $1.cue.index : $0.word.at < $1.word.at }
        var previousEnd: Int?
        var rows: [JSONValue] = []
        for (index, entry) in all.enumerated() {
            defer { previousEnd = max(previousEnd ?? entry.word.end, entry.word.end) }
            guard entry.word.end > from, to.map({ entry.word.at < $0 }) ?? true else { continue }
            guard case .object(var row) = entry.word.json(fps: fps) else { continue }
            row["index"] = .integer(index)
            row["item"] = .string(entry.cue.item.id)
            row["cue"] = .integer(entry.cue.index)
            row["timing"] = .string(hasTimedWords(entry.cue.item) ? "transcribed" : "estimated")
            if let previousEnd { row["gapBefore"] = .integer(entry.word.at - previousEnd) }
            rows.append(.object(row))
        }
        return .object([
            "revision": .integer(project.revision), "fps": .number(fps), "count": .integer(rows.count),
            "total": .integer(all.count), "words": .array(rows),
        ])
    }

    /// A word on the timeline: absolute frames and, for a caption made from a media, where it is heard in it.
    struct Word {
        let text: String
        let at: Int
        let end: Int
        let mediaID: String?
        let source: (clip: String, start: Double, end: Double)?

        func json(fps: Double) -> JSONValue {
            var row: [String: JSONValue] = [
                "text": .string(text), "at": .integer(at), "end": .integer(end),
                "atSeconds": .number(rounded(Double(at) / fps)), "endSeconds": .number(rounded(Double(end) / fps)),
            ]
            if let mediaID {
                row["source"] = source.map { source in
                    .object([
                        "media": .string(mediaID), "clip": .string(source.clip),
                        "start": .number(rounded(source.start)), "end": .number(rounded(source.end)),
                    ])
                } ?? .null
            }
            return .object(row)
        }
    }

    static func words(of item: Item, sources: SourceMap) -> [Word] {
        let mediaID = item["captionMedia"]?.string
        let timings = item.wordTimings
        // Words timed outside the caption (the other half of a split, a trimmed end) are not heard during it. A word
        // ends by the next one's start (estimated timings round to overlapping frames).
        return zip(CaptionWords.tokens(item.text), timings.indices).compactMap { text, index in
            let timing = timings[index]
            let next = index + 1 < timings.count ? max(timings[index + 1].at, timing.at + 1) : Int.max
            let at = max(item.at, item.at + timing.at)
            let end = min(item.end, item.at + min(timing.at + timing.duration, next))
            guard end > at else { return nil }
            return Word(
                text: text, at: at, end: end, mediaID: mediaID,
                source: mediaID.flatMap { sources.heard($0, from: at, to: end) })
        }
    }

    static func hasTimedWords(_ item: Item) -> Bool {
        guard case .array(let list) = item["words"] else { return false }
        return list.count == CaptionWords.tokens(item.text).count
    }

    /// Source seconds of a media at timeline frames, through the clip where it is heard at the span's middle.
    struct SourceMap {
        let project: Project
        let clips: [String: [(item: Item, media: Media)]]

        init(_ project: Project) {
            self.project = project
            let used = Set(project.tracks.flatMap(\.items).compactMap { $0["captionMedia"]?.string })
            clips = Dictionary(uniqueKeysWithValues: used.map { ($0, project.audibleClips($0)) })
        }

        func heard(_ mediaID: String, from: Int, to: Int) -> (clip: String, start: Double, end: Double)? {
            let middle = (from + to) / 2
            guard let heard = clips[mediaID]?.first(where: { $0.item.at <= middle && middle < $0.item.end }) else {
                return nil
            }
            let clip = heard.item, media = heard.media
            let sourceFPS = media.fps.value > 0 ? media.fps.value : project.fps.value
            let sourceStart = Double(clip.sourceIn) / sourceFPS
            let seconds = { (frame: Int) in
                sourceStart + clip.sourceSeconds(afterFrames: min(max(frame, clip.at), clip.end) - clip.at, fps: project.fps)
            }
            return (clip.id, seconds(from), seconds(to))
        }
    }

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The text as read: lines joined by one space (characters per second counts these characters).
    static func oneLine(_ text: String) -> String { lines(text).joined(separator: " ") }

    static func clock(_ seconds: Double) -> String {
        let milliseconds = Int((seconds * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d.%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60,
            milliseconds / 1000 % 60, milliseconds % 1000)
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
