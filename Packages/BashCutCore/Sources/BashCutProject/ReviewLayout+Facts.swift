import Foundation

/// Facts about text and pictures on screen for `review.layout` (P0-B6): how long a text holds and how fast it must
/// be read, how it sits against the speech, whether it covers a caption, how often its template repeats and how
/// much text there is per minute; at a frame, the pictures on screen with their scale and coverage. Faces come from
/// the boxes `media.subjects` stored for the media under the text (`FaceOverlap`); without any, face fields are null
/// (unknown), never "no face". No verdicts.
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
            "faceOverlap": FaceOverlap.measure(
                bounds(item, project: project, context: context), from: item.at, to: item.end, project: project,
                subjects: context.subjects)?.json ?? .null,
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
    static func pictures(_ project: Project, at frame: Int, subjects: [String: MediaSubjects] = [:]) -> JSONValue {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [JSONValue] = []
        for track in project.tracks where track.kind == TrackKind.video && track["hidden"] != .bool(true) {
            for item in track.items where item.at <= frame && frame < item.end {
                var row: [String: JSONValue] = ["id": .string(item.id), "track": .string(track.id), "role": .string(track.role)]
                if let asset = item.mediaID.flatMap({ media[$0] }) {
                    row["media"] = .string(asset.id)
                    row["scale"] = ReviewScale.json(item, media: asset, project: project) ?? .null
                    // A graphic or picture-in-picture over another clip: its box against the faces below it.
                    if track.role != TrackRole.main, let placement = PicturePlacement(item, media: asset, project: project) {
                        let values = FaceOverlap.transform(item, at: frame - item.at)
                        let whole = MediaSubjects.Box(x: 0, y: 0, width: 1, height: 1)
                        let box = placement.frameRect(whole, zoom: values.zoom, pan: values.pan, tilt: values.tilt)
                        row["faceOverlap"] = FaceOverlap.measure(
                            box, topLeft: true, from: frame, to: frame + 1, project: project, subjects: subjects,
                            excluding: item.id)?.json ?? .null
                    }
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

/// How much of a face a box on screen covers (P0-B6): face boxes stored for the clips playing under it
/// (`media.subjects`), placed in the frame as the renderer places their picture (fit or fill, zoom, pan and tilt with
/// keyframes; rotation is not followed), at each sampled picture the box is on screen for. Raw ratios, no verdict.
enum FaceOverlap {
    struct Result {
        /// The largest share of one face box the box covers, 0 when it covers none.
        let ratio: Double
        let frame: Int?
        let item: String?
        let media: String?
        let confidence: Double?
        /// Sampled pictures with at least one face, while the box is on screen.
        let samples: Int

        var json: JSONValue {
            .object([
                "ratio": .number(ReviewLayout.rounded(ratio)), "frame": frame.map(JSONValue.integer) ?? .null,
                "item": item.map(JSONValue.string) ?? .null, "media": media.map(JSONValue.string) ?? .null,
                "confidence": confidence.map { .number(ReviewLayout.rounded($0)) } ?? .null, "samples": .integer(samples),
            ])
        }
    }

    /// Zoom, pan and tilt of `item` at `frame` from its start (keys, else its transform).
    static func transform(_ item: Item, at frame: Int) -> (zoom: Double, pan: Double, tilt: Double) {
        let transform = item["transform"]?.object ?? [:]
        let motion = item.motion
        let value = { (key: String, fallback: Double) in
            motion?.value(key, at: Double(frame)) ?? transform[key]?.double ?? fallback
        }
        return (value("zoom", 1), value("pan", 0), value("tilt", 0))
    }

    /// The sampled pictures `clip` shows over `frames` (from its start), each from the frame it first shows; the
    /// picture already showing at the first frame counts from there.
    static func pictures(
        _ clip: Item, media: Media, project: Project, subjects: MediaSubjects, frames: Range<Int>
    ) -> [(frame: Int, sample: MediaSubjects.Sample)] {
        let start = frames.lowerBound
        let rows = SubjectReframe.timeline(clip, media: media, project: project, subjects: subjects)
            .filter { $0.frame < frames.upperBound }
        guard let showing = rows.last(where: { $0.frame <= start }) else { return rows.filter { $0.frame >= start } }
        return [(start, showing.sample)] + rows.filter { $0.frame > start }
    }

    /// The overlap of `box` (frame pixels; from the bottom left unless `topLeft`) with the faces under it from frame
    /// `from` to `to`; nil when no clip there has stored boxes (unknown).
    static func measure(
        _ box: CGRectLike, topLeft: Bool = false, from: Int, to: Int, project: Project,
        subjects: [String: MediaSubjects], excluding: String? = nil
    ) -> Result? {
        guard !subjects.isEmpty, project.height > 0 else { return nil }
        let rect = topLeft ? box : CGRectLike(
            x: box.x, y: Double(project.height) - box.y - box.height, width: box.width, height: box.height)
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var known = false
        var best: Result?
        var samples = 0
        for track in project.tracks where track.kind == TrackKind.video && track["hidden"] != .bool(true) {
            for clip in track.items where clip.id != excluding && clip.at < to && from < clip.end {
                guard let asset = clip.mediaID.flatMap({ media[$0] }), let stored = subjects[asset.id],
                    let placement = PicturePlacement(clip, media: asset, project: project)
                else { continue }
                known = true
                let start = max(from, clip.at) - clip.at, end = min(to, clip.end) - clip.at
                for (frame, sample) in pictures(clip, media: asset, project: project, subjects: stored, frames: start..<end)
                where !sample.faces.isEmpty {
                    samples += 1
                    let values = transform(clip, at: frame)
                    for face in sample.faces {
                        let placed = placement.frameRect(face, zoom: values.zoom, pan: values.pan, tilt: values.tilt)
                        let area = placed.width * placed.height
                        let ratio = area > 0 ? min(1, TextFacts.intersection(rect, placed) / area) : 0
                        if ratio > (best?.ratio ?? -1) {
                            best = Result(
                                ratio: ratio, frame: clip.at + frame, item: clip.id, media: asset.id,
                                confidence: face.confidence, samples: 0)
                        }
                    }
                }
            }
        }
        guard known else { return nil }
        guard let best, best.ratio > 0 else {
            return Result(ratio: 0, frame: nil, item: nil, media: nil, confidence: nil, samples: samples)
        }
        return Result(
            ratio: best.ratio, frame: best.frame, item: best.item, media: best.media, confidence: best.confidence,
            samples: samples)
    }
}
