import Foundation

/// `clip.reframe` (P3-J1): a crop that keeps the subject in frame, from the face (or person) boxes `media.subjects`
/// measured. The clip fills the frame and is panned (and tilted) so the subject's centre sits at an anchor:
/// `locked` holds one framing for the whole clip, `cut` jumps to a new framing when the subject drifts off its
/// anchor, `follow` moves with the subject. Every limit is a parameter. When too few pictures have a subject, or the
/// share of the subject the framing keeps in view is below the gate, it falls back to fitting the whole picture or
/// refuses; it never crops the centre blind. Returns the coverage it measured either way.
public enum SubjectReframe {
    public enum Mode: String, Sendable, CaseIterable {
        case locked, cut, follow
    }

    /// Which boxes make the subject in each picture.
    public enum Subject: String, Sendable, CaseIterable {
        /// The largest face.
        case face
        /// All faces together (their union).
        case faces
        /// The largest person box.
        case person
    }

    public enum Fallback: String, Sendable, CaseIterable {
        case fit, refuse
    }

    public struct Options: Sendable, Equatable {
        public var mode: Mode = .locked
        public var subject: Subject = .face
        /// Boxes below this confidence are ignored.
        public var minConfidence = 0.5
        /// Where the subject's centre sits in the frame, as shares from the top left.
        public var anchorX = 0.5
        public var anchorY = 0.5
        /// Scale over the filled size.
        public var zoom = 1.0
        /// The least mean share of the subject box kept in view, over pictures with a subject.
        public var gate = 0.9
        /// The least share of the clip's sampled pictures that must have a subject.
        public var minSubjectShare = 0.5
        public var fallback: Fallback = .fit
        /// `cut`: how far (share of the frame's width or height) the subject's centre may move off its anchor
        /// before the framing changes.
        public var drift = 0.15
        /// `cut`: the shortest time one framing is held, in seconds.
        public var minHoldSeconds = 1.0
        /// `follow`: the window the subject's path is averaged over, in seconds.
        public var smoothSeconds = 1.0

        public init() {}
    }

    /// One framing held from `frame` (from the item's start).
    public struct Segment: Sendable, Equatable {
        public let frame: Int
        public let pan: Double
        public let tilt: Double

        var json: JSONValue {
            .object(["frame": .integer(frame), "pan": .number(rounded(pan, 10)), "tilt": .number(rounded(tilt, 10))])
        }
    }

    public struct Coverage: Sendable, Equatable {
        /// Pictures sampled inside the clip, and those with a subject.
        public let samples: Int
        public let subjectSamples: Int
        /// Mean and least share of the subject box in view, over pictures with a subject; nil without any.
        public let mean: Double?
        public let min: Double?

        public var subjectShare: Double { samples > 0 ? Double(subjectSamples) / Double(samples) : 0 }

        public var json: JSONValue {
            .object([
                "samples": .integer(samples), "subjectSamples": .integer(subjectSamples),
                "subjectShare": .number(rounded(subjectShare, 1_000)),
                "mean": mean.map { .number(rounded($0, 1_000)) } ?? .null,
                "min": min.map { .number(rounded($0, 1_000)) } ?? .null,
            ])
        }
    }

    public struct Plan: Sendable, Equatable {
        /// `reframe` when the framing passed the gate, `fit` when it fell back.
        public let applied: String
        /// Why it fell back; nil when it reframed.
        public let reason: String?
        /// The item patch (one `setProperties`): fill, transform and keyframes.
        public let patch: [String: JSONValue]
        public let coverage: Coverage
        public let segments: [Segment]
        /// Item frames worth looking at: each framing's start and the picture with the least coverage.
        public let previewFrames: [Int]

        public var json: JSONValue {
            .object([
                "applied": .string(applied), "reason": reason.map(JSONValue.string) ?? .null,
                "coverage": coverage.json, "segments": .array(segments.map(\.json)),
                "transform": patch["transform"] ?? .null, "fill": patch["fill"] ?? .null,
            ])
        }
    }

    public struct Refused: Error, LocalizedError, Sendable {
        public let reason: String
        public let coverage: Coverage
        public var errorDescription: String? { reason }
    }

    /// The source second each item frame shows, honouring speed, speed curves and freeze frames.
    static func sourceSeconds(_ item: Item, media: Media, project: Project, frame: Int) -> Double {
        if media.isImage { return 0 }
        if let freeze = item["freezeFrame"]?.int { return Double(freeze) / max(0.001, media.fps.value) }
        return Double(item.sourceIn) / max(0.001, media.fps.value)
            + item.sourceSeconds(afterFrames: frame, fps: project.fps)
    }

    /// The source seconds the item plays, from its first to its last frame.
    public static func sourceRange(_ item: Item, media: Media, project: Project) -> ClosedRange<Double> {
        let first = sourceSeconds(item, media: media, project: project, frame: 0)
        let last = sourceSeconds(item, media: media, project: project, frame: max(0, item.duration - 1))
        return min(first, last)...max(first, last)
    }

    /// Each sampled picture the item shows, with the item frame it first appears at.
    static func timeline(_ item: Item, media: Media, project: Project, subjects: MediaSubjects)
        -> [(frame: Int, sample: MediaSubjects.Sample)]
    {
        var rows: [(frame: Int, sample: MediaSubjects.Sample)] = []
        if media.isImage {
            if let sample = subjects.sample(near: 0, tolerance: .infinity) { rows.append((0, sample)) }
            return rows
        }
        var last: Double?
        for frame in 0..<max(0, item.duration) {
            let seconds = sourceSeconds(item, media: media, project: project, frame: frame)
            guard let sample = subjects.sample(near: seconds), sample.seconds != last else { continue }
            last = sample.seconds
            rows.append((frame, sample))
        }
        return rows
    }

    static func subjectBox(_ sample: MediaSubjects.Sample, options: Options) -> MediaSubjects.Box? {
        let pool = (options.subject == .person ? sample.people : sample.faces)
            .filter { $0.confidence >= options.minConfidence && $0.area > 0 }
        guard let largest = pool.max(by: { $0.area < $1.area }) else { return nil }
        return options.subject == .faces ? pool.dropFirst().reduce(pool[0]) { $0.union($1) } : largest
    }

    /// Pan and tilt that put `center` (shares of the source picture) at the anchor, kept so no edge of the picture
    /// comes inside the frame.
    static func framing(center: (x: Double, y: Double), placement: PicturePlacement, options: Options) -> (pan: Double, tilt: Double) {
        let scale = placement.baseScale * options.zoom
        let width = placement.sourceWidth, height = placement.sourceHeight
        var pan = (0.5 - center.x) * width * scale + (options.anchorX - 0.5) * placement.canvasWidth
        var tilt = (center.y - 0.5) * height * scale - (options.anchorY - 0.5) * placement.canvasHeight
        let spareX = max(0, (width * scale - placement.canvasWidth) / 2)
        let spareY = max(0, (height * scale - placement.canvasHeight) / 2)
        pan = Swift.min(spareX, Swift.max(-spareX, pan))
        tilt = Swift.min(spareY, Swift.max(-spareY, tilt))
        return (pan, tilt)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    /// Plans the reframe of a video or image `item`; throws `Refused` when it falls short and the fallback is
    /// `refuse`.
    public static func plan(
        _ item: Item, media: Media, project: Project, subjects: MediaSubjects, options: Options
    ) throws -> Plan {
        guard let width = media.width, let height = media.height, width > 0, height > 0, project.width > 0,
            project.height > 0
        else { throw ProjectError.invalid("The clip's picture size is unknown") }
        let fill = PicturePlacement(
            sourceWidth: Double(width), sourceHeight: Double(height), canvasWidth: Double(project.width),
            canvasHeight: Double(project.height), fill: true)
        let rows = timeline(item, media: media, project: project, subjects: subjects)
        let boxes = rows.map { (frame: $0.frame, box: subjectBox($0.sample, options: options)) }
        let found = boxes.compactMap { row in row.box.map { (frame: row.frame, box: $0) } }
        let fps = project.fps.value
        let crop = item["crop"]?.object ?? [:]

        func coverage(_ at: (Int) -> (pan: Double, tilt: Double)) -> Coverage {
            let shares = found.map { row in
                let framing = at(row.frame)
                return fill.visibleShare(row.box, zoom: options.zoom, pan: framing.pan, tilt: framing.tilt, crop: crop)
            }
            return Coverage(
                samples: rows.count, subjectSamples: found.count,
                mean: shares.isEmpty ? nil : shares.reduce(0, +) / Double(shares.count), min: shares.min())
        }

        var segments: [Segment] = []
        var keyed: [(frame: Int, pan: Double, tilt: Double)] = []
        if !found.isEmpty {
            let targets = found.map { row in
                (frame: row.frame, framing: framing(center: (row.box.centerX, row.box.centerY), placement: fill, options: options),
                 center: (x: row.box.centerX, y: row.box.centerY))
            }
            switch options.mode {
            case .locked:
                let center = (median(targets.map(\.center.x)), median(targets.map(\.center.y)))
                let held = framing(center: center, placement: fill, options: options)
                segments = [Segment(frame: 0, pan: held.pan, tilt: held.tilt)]
            case .cut:
                let hold = Int((options.minHoldSeconds * fps).rounded())
                var groups: [[Int]] = [[0]]
                var current = targets[0].framing
                for index in targets.indices.dropFirst() {
                    let target = targets[index]
                    let start = targets[groups[groups.count - 1][0]].frame
                    let offX = abs(target.framing.pan - current.pan) / max(1, fill.canvasWidth)
                    let offY = abs(target.framing.tilt - current.tilt) / max(1, fill.canvasHeight)
                    if max(offX, offY) > options.drift, target.frame - start >= hold {
                        groups.append([index])
                        current = target.framing
                    } else {
                        groups[groups.count - 1].append(index)
                    }
                }
                segments = groups.enumerated().map { number, group in
                    let center = (median(group.map { targets[$0].center.x }), median(group.map { targets[$0].center.y }))
                    let held = framing(center: center, placement: fill, options: options)
                    return Segment(frame: number == 0 ? 0 : targets[group[0]].frame, pan: held.pan, tilt: held.tilt)
                }
            case .follow:
                let window = max(0, options.smoothSeconds * fps / 2)
                keyed = targets.map { target in
                    let near = targets.filter { abs(Double($0.frame - target.frame)) <= window }
                    return (target.frame, near.map(\.framing.pan).reduce(0, +) / Double(near.count),
                            near.map(\.framing.tilt).reduce(0, +) / Double(near.count))
                }
                // At most 1,000 keys, evenly picked.
                if keyed.count > 1_000 {
                    let stride = Double(keyed.count - 1) / 999
                    keyed = (0..<1_000).map { keyed[Int((Double($0) * stride).rounded())] }
                }
                if keyed[0].frame != 0 { keyed[0].frame = 0 }
                segments = keyed.map { Segment(frame: $0.frame, pan: $0.pan, tilt: $0.tilt) }
            }
        }

        func framingAt(_ frame: Int) -> (pan: Double, tilt: Double) {
            if options.mode == .follow, !keyed.isEmpty {
                let motion = ItemMotion(keys: [
                    "pan": keyed.map { .init(frame: $0.frame, value: $0.pan, ease: .linear) },
                    "tilt": keyed.map { .init(frame: $0.frame, value: $0.tilt, ease: .linear) },
                ])
                return (motion.value("pan", at: Double(frame)) ?? 0, motion.value("tilt", at: Double(frame)) ?? 0)
            }
            let segment = segments.last { $0.frame <= frame } ?? segments.first
            return (segment?.pan ?? 0, segment?.tilt ?? 0)
        }
        let measured = coverage(framingAt)

        var transform = item["transform"]?.object ?? [:]
        var motion = item.motion ?? ItemMotion(keys: [:])
        for property in ["zoom", "pan", "tilt"] { motion.keys[property] = nil }
        let failure: String? = {
            if rows.isEmpty { return "No subject boxes are stored for the source this clip plays" }
            if measured.subjectShare < options.minSubjectShare {
                return "A subject was found in \(percent(measured.subjectShare)) of the pictures, under minSubjectShare "
                    + percent(options.minSubjectShare)
            }
            if let mean = measured.mean, mean < options.gate {
                return "The framing keeps \(percent(mean)) of the subject in view on average, under the gate \(percent(options.gate))"
            }
            return nil
        }()
        if let failure {
            if options.fallback == .refuse { throw Refused(reason: failure, coverage: measured) }
            transform["zoom"] = .number(1)
            transform["pan"] = .number(0)
            transform["tilt"] = .number(0)
            return Plan(
                applied: "fit", reason: failure,
                patch: ["fill": .bool(false), "transform": .object(transform), "keyframes": motion.isEmpty ? .null : motion.json,
                        "reframePreset": .string("custom")],
                coverage: measured, segments: [], previewFrames: [item.duration / 2])
        }
        transform["zoom"] = .number(rounded(options.zoom, 1_000))
        transform["pan"] = .number(rounded(segments[0].pan, 10))
        transform["tilt"] = .number(rounded(segments[0].tilt, 10))
        if segments.count > 1 {
            let ease: ItemMotion.Ease = options.mode == .cut ? .hold : .linear
            motion.keys["pan"] = segments.map { .init(frame: $0.frame, value: rounded($0.pan, 10), ease: ease) }
            motion.keys["tilt"] = segments.map { .init(frame: $0.frame, value: rounded($0.tilt, 10), ease: ease) }
        }
        var previews = options.mode == .follow ? [0, item.duration / 2, max(0, item.duration - 1)] : segments.map(\.frame)
        if let worst = found.min(by: { lhs, rhs in
            let left = framingAt(lhs.frame), right = framingAt(rhs.frame)
            return fill.visibleShare(lhs.box, zoom: options.zoom, pan: left.pan, tilt: left.tilt, crop: crop)
                < fill.visibleShare(rhs.box, zoom: options.zoom, pan: right.pan, tilt: right.tilt, crop: crop)
        }) { previews.append(worst.frame) }
        previews = Array(Set(previews.map { min(max(0, $0), max(0, item.duration - 1)) })).sorted()
        return Plan(
            applied: "reframe", reason: nil,
            patch: ["fill": .bool(true), "transform": .object(transform), "keyframes": motion.isEmpty ? .null : motion.json,
                    "reframePreset": .string("custom")],
            coverage: measured, segments: segments, previewFrames: Array(previews.prefix(12)))
    }

    static func percent(_ share: Double) -> String { String(format: "%g%%", (share * 1_000).rounded() / 10) }
}

private func rounded(_ value: Double, _ places: Double) -> Double { (value * places).rounded() / places }
