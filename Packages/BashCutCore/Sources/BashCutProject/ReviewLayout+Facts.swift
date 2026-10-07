import Foundation

/// Facts about text and pictures on screen for `review.layout` (P0-B6): how long a text holds and how fast it must
/// be read, how it sits against the speech, whether it covers a caption, how often its template repeats and how
/// much text there is per minute; at a frame, the pictures on screen with their scale and coverage. Faces need a
/// `vision.faces` provider: until there is one, face fields are null (unknown), never "no face". No verdicts.
enum TextFacts {
    /// What every item is measured against.
    struct Scene {
        let project: Project
        let context: ReviewContext
        /// Every text item on a visible layer.
        let all: [(Track, Item)]
        let words: [ReviewSync.WordSpan]?
    }

    static func json(_ item: Item, track: Track, in scene: Scene) -> [String: JSONValue] {
        let (project, context, all, words) = (scene.project, scene.context, scene.all, scene.words)
        let fps = project.fps.value
        let hold = Double(item.duration) / fps
        let count = item.text.split(whereSeparator: { $0.isWhitespace }).count
        var row: [String: JSONValue] = [
            "holdSeconds": .number(ReviewLayout.rounded(hold)), "words": .integer(count),
            "wordsPerSecond": .number(hold > 0 ? ReviewLayout.rounded(Double(count) / hold) : 0),
            "faceOverlap": .null,
        ]
        if let words {
            let starts = words.map(\.at).sorted()
            let spoken = words.reduce(0) { total, word in
                total + max(0, min(word.end, item.end) - max(word.at, item.at))
            }
            row["speech"] = .object([
                "onsetOffsetFrames": ReviewSync.nearest(starts, to: item.at).map { .integer(item.at - $0) } ?? .null,
                "narrationShare": .number(item.duration > 0 ? ReviewLayout.rounded(min(1, Double(spoken) / Double(item.duration))) : 0),
            ])
        }
        if track.role != TrackRole.captions {
            let box = bounds(item, project: project, context: context)
            var overlap: (id: String, ratio: Double)?
            for (other, caption) in all where other.role == TrackRole.captions && caption.at < item.end && item.at < caption.end {
                let ratio = intersection(box, bounds(caption, project: project, context: context)) / max(1, box.width * box.height)
                if ratio > (overlap?.ratio ?? 0) { overlap = (caption.id, ratio) }
            }
            row["captionOverlap"] = overlap.map {
                .object(["item": .string($0.id), "ratio": .number(ReviewLayout.rounded($0.ratio))])
            } ?? .null
        }
        let preset = item.textPreset ?? ""
        row["templateRepeats"] = .integer(all.filter { $0.0.id == track.id && ($0.1.textPreset ?? "") == preset }.count)
        return row
    }

    /// Text box in frame pixels from the bottom-left, as the renderer lays it out.
    static func bounds(_ item: Item, project: Project, context: ReviewContext) -> CGRectLike {
        let box = TimelineReview.textBox(item, width: Double(project.width), height: Double(project.height), context: context)
        return CGRectLike(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY)
    }

    static func intersection(_ left: CGRectLike, _ right: CGRectLike) -> Double {
        let width = min(left.x + left.width, right.x + right.width) - max(left.x, right.x)
        let height = min(left.y + left.height, right.y + right.height) - max(left.y, right.y)
        return max(0, width) * max(0, height)
    }

    /// Titles (text items outside the caption layer) and captions per minute of the edit.
    static func density(_ all: [(Track, Item)], project: Project) -> JSONValue {
        let minutes = Double(project.duration) / project.fps.value / 60
        let titles = all.filter { $0.0.role != TrackRole.captions }.count
        let captions = all.count - titles
        let rate = { (count: Int) in JSONValue.number(minutes > 0 ? ReviewLayout.rounded(Double(count) / minutes) : 0) }
        return .object([
            "titles": .integer(titles), "captions": .integer(captions), "titlesPerMinute": rate(titles),
            "captionsPerMinute": rate(captions),
        ])
    }

    /// The video and image items on screen at `frame`, top layer first, with their scale facts (`ReviewScale`).
    static func pictures(_ project: Project, at frame: Int) -> JSONValue {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [JSONValue] = []
        for track in project.tracks where track.kind == TrackKind.video && track["hidden"] != .bool(true) {
            for item in track.items where item.at <= frame && frame < item.end {
                var row: [String: JSONValue] = ["id": .string(item.id), "track": .string(track.id), "role": .string(track.role)]
                if let asset = item.mediaID.flatMap({ media[$0] }) {
                    row["media"] = .string(asset.id)
                    row["scale"] = ReviewScale.json(item, media: asset, project: project) ?? .null
                }
                row["subjectClipped"] = .null
                rows.append(.object(row))
            }
        }
        return .array(rows)
    }
}

/// A rectangle without CoreGraphics, so the core stays platform-neutral.
struct CGRectLike: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
