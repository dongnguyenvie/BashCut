import Foundation

/// The face and person boxes a `vision.faces` provider found in one media file (`media.subjects`, P2-H6), as the app
/// keeps them per file content: one entry per sampled source second. Boxes are `[x, y, width, height]` as shares of
/// the upright picture from its top left. Raw boxes only; which face matters is the caller's.
public struct MediaSubjects: Sendable, Equatable {
    public struct Box: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var confidence: Double

        public init(x: Double, y: Double, width: Double, height: Double, confidence: Double = 1) {
            (self.x, self.y, self.width, self.height, self.confidence) = (x, y, width, height, confidence)
        }

        public var area: Double { width * height }
        public var centerX: Double { x + width / 2 }
        public var centerY: Double { y + height / 2 }

        /// The smallest box holding both.
        public func union(_ other: Box) -> Box {
            let left = min(x, other.x), top = min(y, other.y)
            let right = max(x + width, other.x + other.width), bottom = max(y + height, other.y + other.height)
            return Box(x: left, y: top, width: right - left, height: bottom - top, confidence: min(confidence, other.confidence))
        }

        init?(json: JSONValue) {
            let box = json.object["box"]?.array.compactMap(\.double) ?? []
            guard box.count == 4, box.allSatisfy(\.isFinite) else { return nil }
            self.init(x: box[0], y: box[1], width: box[2], height: box[3], confidence: json.object["confidence"]?.double ?? 1)
        }

        var json: JSONValue {
            .object([
                "box": .array([x, y, width, height].map { .number(($0 * 10_000).rounded() / 10_000) }),
                "confidence": .number((confidence * 1_000).rounded() / 1_000),
            ])
        }
    }

    public struct Sample: Sendable, Equatable {
        /// Source seconds of the sampled picture.
        public var seconds: Double
        public var faces: [Box]
        public var people: [Box]

        public init(seconds: Double, faces: [Box], people: [Box] = []) {
            (self.seconds, self.faces, self.people) = (seconds, faces, people)
        }
    }

    /// Sorted by `seconds`, one per second value.
    public private(set) var samples: [Sample]
    /// Seconds between pictures of the run that measured most of them.
    public var step: Double
    /// The provider that found them (`{plugin, version, …}` as the capability reported it).
    public var provider: JSONValue

    public init(samples: [Sample], step: Double, provider: JSONValue = .null) {
        self.samples = Self.sorted(samples)
        self.step = step
        self.provider = provider
    }

    /// From a `media.subjects` result or a stored record: `{step, frames [{seconds, faces, people}], provider}`.
    public init(json: JSONValue) {
        let fields = json.object
        let frames = fields["frames"]?.array ?? []
        let samples = frames.compactMap { frame -> Sample? in
            guard let seconds = frame.object["seconds"]?.double, seconds.isFinite else { return nil }
            return Sample(
                seconds: seconds, faces: (frame.object["faces"]?.array ?? []).compactMap(Box.init(json:)),
                people: (frame.object["people"]?.array ?? []).compactMap(Box.init(json:)))
        }
        self.init(samples: samples, step: fields["step"]?.double ?? 1, provider: fields["provider"] ?? .null)
    }

    public var json: JSONValue {
        .object([
            "step": .number(step), "provider": provider,
            "frames": .array(samples.map { sample in
                .object([
                    "seconds": .number((sample.seconds * 1_000).rounded() / 1_000),
                    "faces": .array(sample.faces.map(\.json)), "people": .array(sample.people.map(\.json)),
                ])
            }),
        ])
    }

    /// These samples with `other`'s added; a picture sampled again (same millisecond) takes the newer boxes.
    public func merging(_ other: MediaSubjects) -> MediaSubjects {
        var byTime: [Int: Sample] = [:]
        for sample in samples + other.samples { byTime[Int((sample.seconds * 1_000).rounded())] = sample }
        return MediaSubjects(
            samples: Array(byTime.values), step: other.samples.count >= samples.count ? other.step : step,
            provider: other.provider == .null ? provider : other.provider)
    }

    /// The sample nearest `seconds` within `tolerance` (half the step by default), or nil.
    public func sample(near seconds: Double, tolerance: Double? = nil) -> Sample? {
        guard !samples.isEmpty else { return nil }
        let limit = tolerance ?? max(step / 2, 0.001) + 0.000_5
        var low = 0, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].seconds < seconds { low = middle + 1 } else { high = middle }
        }
        let candidates = [low - 1, low].filter { samples.indices.contains($0) }
        guard let best = candidates.min(by: { abs(samples[$0].seconds - seconds) < abs(samples[$1].seconds - seconds) }),
            abs(samples[best].seconds - seconds) <= limit
        else { return nil }
        return samples[best]
    }

    /// Samples from `from` to `to` source seconds (inclusive, with a millisecond's slack).
    public func samples(from: Double, to: Double) -> [Sample] {
        samples.filter { $0.seconds >= from - 0.001 && $0.seconds <= to + 0.001 }
    }

    private static func sorted(_ samples: [Sample]) -> [Sample] {
        var seen = Set<Int>()
        return samples.sorted { $0.seconds < $1.seconds }.filter { seen.insert(Int(($0.seconds * 1_000).rounded())).inserted }
    }
}

/// Where a video item's picture sits in the output frame, as the renderer places it (fit or fill, then zoom, pan and
/// tilt; rotation is not followed), for mapping source boxes to frame pixels.
public struct PicturePlacement: Sendable, Equatable {
    /// Upright source picture size in pixels.
    public let sourceWidth: Double
    public let sourceHeight: Double
    public let canvasWidth: Double
    public let canvasHeight: Double
    /// Fit or fill scale before the item's zoom.
    public let baseScale: Double

    public init(sourceWidth: Double, sourceHeight: Double, canvasWidth: Double, canvasHeight: Double, fill: Bool) {
        (self.sourceWidth, self.sourceHeight, self.canvasWidth, self.canvasHeight) =
            (sourceWidth, sourceHeight, canvasWidth, canvasHeight)
        let horizontal = canvasWidth / max(1, sourceWidth), vertical = canvasHeight / max(1, sourceHeight)
        baseScale = fill ? max(horizontal, vertical) : min(horizontal, vertical)
    }

    /// The item's placement in `project`, or nil when its media has no known size.
    public init?(_ item: Item, media: Media, project: Project) {
        guard let width = media.width, let height = media.height, width > 0, height > 0, project.width > 0,
            project.height > 0
        else { return nil }
        self.init(
            sourceWidth: Double(width), sourceHeight: Double(height), canvasWidth: Double(project.width),
            canvasHeight: Double(project.height), fill: project.fills(item))
    }

    /// A source box (shares of the picture from its top left) in frame pixels from the frame's top left, at `zoom`,
    /// `pan` and `tilt` (output pixels; tilt is up).
    func frameRect(_ box: MediaSubjects.Box, zoom: Double, pan: Double, tilt: Double) -> CGRectLike {
        let scale = baseScale * zoom
        let left = (canvasWidth - sourceWidth * scale) / 2 + pan
        let top = (canvasHeight - sourceHeight * scale) / 2 - tilt
        return CGRectLike(
            x: left + box.x * sourceWidth * scale, y: top + box.y * sourceHeight * scale,
            width: box.width * sourceWidth * scale, height: box.height * sourceHeight * scale)
    }

    /// The share of `box` (shares of the source picture) inside the frame and inside `crop` (`{left, right, top,
    /// bottom}` shares of the picture hidden), at `zoom`, `pan` and `tilt`.
    public func visibleShare(
        _ box: MediaSubjects.Box, zoom: Double, pan: Double, tilt: Double, crop: [String: JSONValue] = [:]
    ) -> Double {
        guard box.area > 0 else { return 0 }
        let rect = frameRect(box, zoom: zoom, pan: pan, tilt: tilt)
        let scale = baseScale * zoom
        let left = (canvasWidth - sourceWidth * scale) / 2 + pan
        let top = (canvasHeight - sourceHeight * scale) / 2 - tilt
        let side = { (key: String) in min(0.95, max(0, crop[key]?.double ?? 0)) }
        let shown = CGRectLike(
            x: max(0, left + side("left") * sourceWidth * scale), y: max(0, top + side("top") * sourceHeight * scale),
            width: 0, height: 0)
        let right = min(canvasWidth, left + (1 - side("right")) * sourceWidth * scale)
        let bottom = min(canvasHeight, top + (1 - side("bottom")) * sourceHeight * scale)
        let visible = CGRectLike(x: shown.x, y: shown.y, width: max(0, right - shown.x), height: max(0, bottom - shown.y))
        let area = rect.width * rect.height
        return area > 0 ? min(1, TextFacts.intersection(rect, visible) / area) : 0
    }
}
