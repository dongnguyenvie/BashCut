import Foundation

/// What an export actually wrote, measured from the file (P1-E6): stream starts and the drift between picture and
/// sound, frame rate and size against the preset, and black and silent stretches. Review reads the facts of the
/// current revision: a drift over a frame, a wrong rate or size and black inside the edit are errors; silence is info.
public struct DeliveredFacts: Sendable, Equatable {
    public var revision: Int
    public var preset: String
    public var path: String
    public var videoStart: Double
    public var audioStart: Double?
    /// The rate frames are written at (from the shortest frame duration).
    public var fps: Double
    /// Frames over duration: lower than `fps` when the encoder holds a frame (a still or black stretch).
    public var averageFps: Double?
    public var expectedFps: Double
    public var width: Int
    public var height: Int
    public var expectedWidth: Int
    public var expectedHeight: Int
    public var duration: Double
    /// Seconds in the file.
    public var black: [ClosedRange<Double>]
    public var silence: [ClosedRange<Double>]

    public init(
        revision: Int, preset: String, path: String, videoStart: Double, audioStart: Double?, fps: Double, expectedFps: Double,
        size: (Int, Int), expectedSize: (Int, Int), duration: Double, black: [ClosedRange<Double>], silence: [ClosedRange<Double>],
        averageFps: Double? = nil
    ) {
        self.revision = revision
        self.preset = preset
        self.path = path
        self.videoStart = videoStart
        self.audioStart = audioStart
        self.fps = fps
        self.averageFps = averageFps
        self.expectedFps = expectedFps
        (width, height) = size
        (expectedWidth, expectedHeight) = expectedSize
        self.duration = duration
        self.black = black
        self.silence = silence
    }

    /// The rate frames are written at, from their presentation times: frames over the time of those no longer than
    /// 1.5 × the median frame, so held frames (a still or black stretch written as one long frame) and a coarse
    /// timescale's alternating 20/21-tick frames (29.97 fps at 1/600) do not skew it. Nil under two frames.
    public static func writtenRate(_ times: [Double]) -> Double? {
        let sorted = times.sorted()
        let gaps = zip(sorted.dropFirst(), sorted).map { $0 - $1 }.filter { $0 > 0 }
        guard !gaps.isEmpty else { return nil }
        let median = gaps.sorted()[gaps.count / 2]
        let regular = gaps.filter { $0 <= median * 1.5 }
        return Double(regular.count) / regular.reduce(0, +)
    }

    /// Sound start minus picture start, seconds; nil without sound.
    public var drift: Double? { audioStart.map { $0 - videoStart } }

    public var json: JSONValue {
        let round = { (value: Double) in JSONValue.number((value * 1_000).rounded() / 1_000) }
        let ranges = { (list: [ClosedRange<Double>]) in
            JSONValue.array(list.map { .object(["from": round($0.lowerBound), "to": round($0.upperBound)]) })
        }
        return .object([
            "revision": .integer(revision), "preset": .string(preset), "path": .string(path),
            "videoStart": round(videoStart), "audioStart": audioStart.map(round) ?? .null, "drift": drift.map(round) ?? .null,
            "fps": round(fps), "averageFps": averageFps.map(round) ?? .null, "expectedFps": round(expectedFps),
            "width": .integer(width), "height": .integer(height),
            "expectedWidth": .integer(expectedWidth), "expectedHeight": .integer(expectedHeight), "duration": round(duration),
            "black": ranges(black), "silence": ranges(silence),
        ])
    }
}

extension TimelineReview {
    static func deliveredIssues(_ project: Project, delivered: [DeliveredFacts]) -> [ReviewIssue] {
        let fps = project.fps.value
        var issues: [ReviewIssue] = []
        for facts in delivered where facts.revision == project.revision {
            let id = facts.preset
            if let drift = facts.drift, abs(drift) > 1 / fps {
                issues.append(ReviewIssue(
                    id: "delivered-drift-\(id)", title: "Sound and picture start apart in the file",
                    detail: String(format: "%@: sound starts %.3f s %@ the picture.", facts.path, abs(drift), drift > 0 ? "after" : "before"),
                    frame: 0, severity: .error))
            }
            if abs(facts.fps - facts.expectedFps) > 0.01 {
                issues.append(ReviewIssue(
                    id: "delivered-fps-\(id)", title: "Frame rate differs from the preset",
                    detail: String(format: "The file plays at %.3f fps; the project is %.3f.", facts.fps, facts.expectedFps),
                    frame: 0, severity: .error))
            }
            if facts.width != facts.expectedWidth || facts.height != facts.expectedHeight {
                issues.append(ReviewIssue(
                    id: "delivered-size-\(id)", title: "Size differs from the preset",
                    detail: "The file is \(facts.width)×\(facts.height); the preset is \(facts.expectedWidth)×\(facts.expectedHeight).",
                    frame: 0, severity: .error))
            }
            for range in facts.black where range.lowerBound > 0.05 && range.upperBound < facts.duration - 0.05 {
                let frame = Int((range.lowerBound * fps).rounded())
                issues.append(ReviewIssue(
                    id: "delivered-black-\(id)-\(frame)", title: "Black picture in the exported file",
                    detail: String(format: "%.2f–%.2f s of the file is black.", range.lowerBound, range.upperBound),
                    frame: frame, endFrame: Int((range.upperBound * fps).rounded()), severity: .error))
            }
            for range in facts.silence {
                let frame = Int((range.lowerBound * fps).rounded())
                issues.append(ReviewIssue(
                    id: "delivered-silence-\(id)-\(frame)", title: "Silence in the exported file",
                    detail: String(format: "%.2f–%.2f s of the file has no sound.", range.lowerBound, range.upperBound),
                    frame: frame, endFrame: Int((range.upperBound * fps).rounded()), severity: .info))
            }
        }
        return issues
    }
}
