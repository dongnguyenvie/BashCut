import Foundation

/// The opening and the close of the edit as facts (#467, P0-B11, `review.hook`): when the first words are heard, the
/// first title and caption appear and the first cut lands; when each described subject and shot size first shows and
/// how long it stays on screen; and at the end the last title (with its hold and position), the last words and the
/// last cut. Nothing here says what is early or late enough; a project's `review.hookSeconds` is reported as given.
public enum ReviewHook {
    public static func json(_ project: Project, context: ReviewContext, words: [ReviewSync.WordSpan]) -> JSONValue {
        let fps = project.fps.value
        let at = { (frame: Int) -> JSONValue in
            .object(["frame": .integer(frame), "seconds": .number(ReviewShots.rounded(Double(frame) / fps))])
        }
        let main = project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []
        let texts = ReviewLayout.textItems(project, frame: nil)
        let titles = texts.filter { $0.0.role != TrackRole.captions }
        let captions = texts.filter { $0.0.role == TrackRole.captions }
        let spoken = words.sorted { $0.at < $1.at }
        let regions = TimelineReview.speechRegions(project).sorted { $0.at < $1.at }
        let textRow = { (entry: (Track, Item)) -> JSONValue in
            var row = at(entry.1.at).object
            row["item"] = .string(entry.1.id)
            row["text"] = .string(entry.1.text)
            row["holdSeconds"] = .number(ReviewShots.rounded(Double(entry.1.duration) / fps))
            return .object(row)
        }
        var opening: [String: JSONValue] = [
            "hookSeconds": project["review"]?.object["hookSeconds"] ?? .null,
            "firstWords": spoken.first.map { word in
                var row = at(word.at).object
                row["text"] = .string(spoken.prefix(6).map(\.text).joined(separator: " "))
                return .object(row)
            } ?? .null,
            "firstSpeechItem": regions.first.map { at($0.at) } ?? .null,
            "firstTitle": titles.first.map(textRow) ?? .null,
            "firstCaption": captions.first.map(textRow) ?? .null,
            "firstCut": main.dropFirst().first.map { at($0.at) } ?? .null,
        ]
        opening["described"] = described(project, main: main, fps: fps)
        var close: [String: JSONValue] = [
            "duration": at(project.duration),
            "lastWords": spoken.last.map { word in
                var row = at(word.end).object
                row["text"] = .string(spoken.suffix(6).map(\.text).joined(separator: " "))
                return .object(row)
            } ?? .null,
            "lastCut": main.count > 1 ? at(main[main.count - 1].at) : .null,
        ]
        if let last = titles.max(by: { $0.1.end < $1.1.end }) {
            var row = textRow(last).object
            row["end"] = .integer(last.1.end)
            let layout = ReviewLayout.row(last.1, track: last.0, project: project, context: context).object
            row["bounds"] = layout["bounds"]
            row["edges"] = layout["edges"]
            close["lastTitle"] = .object(row)
        } else {
            close["lastTitle"] = .null
        }
        return .object([
            "revision": .integer(project.revision), "opening": .object(opening), "close": .object(close),
            "platform": context.targets.layoutPlatform(for: project).json,
        ])
    }

    /// Per described subject and shot size: the first frame a Main shot shows it and its seconds on screen.
    static func described(_ project: Project, main: [Item], fps: Double) -> JSONValue {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var subjects: [String: (first: Int, frames: Int)] = [:], sizes: [String: (first: Int, frames: Int)] = [:]
        for shot in main {
            guard let asset = shot.mediaID.flatMap({ media[$0] }), let description = asset.shotDescription else { continue }
            let span = project.sourceSpan(of: shot, media: asset)
            guard let facts = description.shot(covering: span.lowerBound, to: span.upperBound) else { continue }
            for subject in facts.subjects {
                let current = subjects[subject] ?? (shot.at, 0)
                subjects[subject] = (min(current.first, shot.at), current.frames + shot.duration)
            }
            if let size = facts.size {
                let current = sizes[size] ?? (shot.at, 0)
                sizes[size] = (min(current.first, shot.at), current.frames + shot.duration)
            }
        }
        let rows = { (values: [String: (first: Int, frames: Int)]) -> JSONValue in
            .array(values.sorted { $0.value.first < $1.value.first }.map { name, value in
                .object([
                    "name": .string(name), "firstFrame": .integer(value.first),
                    "firstSeconds": .number(ReviewShots.rounded(Double(value.first) / fps)),
                    "onScreenSeconds": .number(ReviewShots.rounded(Double(value.frames) / fps)),
                ])
            })
        }
        return .object(["subjects": rows(subjects), "sizes": rows(sizes)])
    }
}
