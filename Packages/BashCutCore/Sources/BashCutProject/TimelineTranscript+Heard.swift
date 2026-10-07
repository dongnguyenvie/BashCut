import Foundation

extension TimelineTranscript {
    /// Words of stored source transcripts as they are heard on the timeline now (P0-A2): every word of a media whose
    /// middle falls inside a clip that plays it (audio clips, the sound of a video clip; muted clips and freeze
    /// frames left out), at timeline frames through that clip's trim and speed. Unlike caption words they follow
    /// the clips, and they keep the provider's confidence, speaker, event and no-speech probability.
    /// `from`/`to` keep the words that overlap that frame span; `media` keeps one media.
    public static func heardWordsJSON(
        _ project: Project, transcripts: [String: SourceTranscript], from: Int = 0, to: Int? = nil,
        media: String? = nil
    ) -> JSONValue {
        let fps = project.fps.value
        var all: [(at: Int, end: Int, row: [String: JSONValue])] = []
        for (mediaID, transcript) in transcripts where media == nil || mediaID == media {
            for (clip, asset) in project.audibleClips(mediaID) where asset.fps.value > 0 {
                let source = project.sourceSpan(of: clip, media: asset)
                let first = transcript.words.partitioningIndex { $0.end > source.lowerBound }
                for word in transcript.words[first...].prefix(while: { $0.start < source.upperBound }) {
                    let middle = (word.start + word.end) / 2
                    guard source.contains(middle) else { continue }
                    let at = max(clip.at, project.frame(atSource: max(word.start, source.lowerBound), in: clip, media: asset))
                    let end = min(clip.end, project.frame(atSource: min(word.end, source.upperBound), in: clip, media: asset))
                    let heard = Word(
                        text: word.text, at: at, end: max(end, at + 1), mediaID: mediaID,
                        source: (clip.id, word.start, word.end))
                    var row = heard.json(fps: fps).object
                    for (key, value) in SourceTranscript.json(word) where !["text", "start", "end"].contains(key) {
                        row[key] = value
                    }
                    row["item"] = .string(clip.id)
                    row["timing"] = .string("source")
                    all.append((heard.at, heard.end, row))
                }
            }
        }
        all.sort { $0.at == $1.at ? $0.end < $1.end : $0.at < $1.at }
        var previousEnd: Int?
        var rows: [JSONValue] = []
        for (index, entry) in all.enumerated() {
            defer { previousEnd = max(previousEnd ?? entry.end, entry.end) }
            guard entry.end > from, to.map({ entry.at < $0 }) ?? true else { continue }
            var row = entry.row
            row["index"] = .integer(index)
            if let previousEnd { row["gapBefore"] = .integer(entry.at - previousEnd) }
            rows.append(.object(row))
        }
        return .object([
            "revision": .integer(project.revision), "fps": .number(fps), "heard": .bool(true),
            "count": .integer(rows.count), "total": .integer(all.count), "words": .array(rows),
        ])
    }
}
