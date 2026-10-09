import Foundation

/// What `media.analysis` derives from a record: the cut list after the agent's corrections, shots with the fields of
/// `review.shots`, shot statistics, and sound spans. The limits are the reader's, with documented defaults, so the
/// agent can read the same record with other limits without measuring again.
extension MediaAnalysis {
    public struct Limits: Sendable, Equatable {
        /// Candidates scoring below this are not cuts.
        public var minScore: Double
        /// Sound counts as active this many dB over the floor.
        public var activityDb: Double
        /// Quiet gaps up to this many seconds inside an active span are bridged.
        public var bridgeSeconds: Double

        public init(minScore: Double = 0.1, activityDb: Double = 10, bridgeSeconds: Double = 0.3) {
            (self.minScore, self.activityDb, self.bridgeSeconds) = (minScore, activityDb, bridgeSeconds)
        }
    }

    /// One cut after corrections: a candidate (with its score) or one the agent added (score nil).
    public struct ListedCut: Sendable, Equatable {
        public let frame: Int
        public let score: Double?
    }

    /// Candidates at or over `minScore` that were not removed, and the added cuts, in frame order.
    public func cuts(minScore: Double) -> [ListedCut] {
        guard let picture else { return [] }
        let removed = corrections.remove
        let kept = picture.candidates.filter { candidate in
            candidate.score >= minScore && !removed.contains { abs($0 - candidate.frame) <= picture.interval }
        }.map { ListedCut(frame: $0.frame, score: $0.score) }
        let added = corrections.add.filter { frame in
            frame > 0 && frame < picture.frames && !kept.contains { $0.frame == frame }
        }.map { ListedCut(frame: $0, score: nil) }
        return (kept + added).sorted { $0.frame < $1.frame }
    }

    /// Adds and removes cuts at source seconds. Removing an added cut takes it back; adding near a removed candidate
    /// restores it. Without a picture measurement there is nothing to correct.
    public mutating func correct(add: [Double], remove: [Double], clear: Bool = false) throws {
        guard let picture else { throw ProjectError.invalid("This media has no picture measurement to correct") }
        if clear { corrections = Corrections() }
        let frame = { (seconds: Double) in Int((seconds * picture.fps).rounded()) }
        for seconds in add + remove where !(seconds.isFinite && seconds > 0 && frame(seconds) < picture.frames) {
            throw ProjectError.invalid(String(format: "%.3f s is not inside the media", seconds))
        }
        for value in remove.map(frame) {
            let near = { (other: Int) in abs(other - value) <= picture.interval }
            if corrections.add.contains(where: near) {
                corrections.add.removeAll(where: near)
            } else if !corrections.remove.contains(value) {
                corrections.remove.append(value)
            }
        }
        for value in add.map(frame) {
            corrections.remove.removeAll { abs($0 - value) <= picture.interval }
            let candidate = picture.candidates.contains { abs($0.frame - value) <= picture.interval }
            if !candidate, !corrections.add.contains(value) { corrections.add.append(value) }
        }
        corrections.add.sort()
        corrections.remove.sort()
    }

    /// Measured shots as source seconds between the cuts at `minScore`; nil without a picture measurement.
    public func shotSpans(minScore: Double = Limits().minScore) -> [(start: Double, end: Double)]? {
        guard let picture, picture.frames > 0, picture.fps > 0 else { return nil }
        let bounds = [0] + cuts(minScore: minScore).map(\.frame) + [picture.frames]
        return zip(bounds, bounds.dropFirst()).filter { $0.1 > $0.0 }.map {
            (Double($0.0) / picture.fps, Double($0.1) / picture.fps)
        }
    }

    /// The samples as a `ReviewPicture`, so shot motion is computed by the same function as `review.shots`.
    var reviewPicture: ReviewPicture? {
        picture.map { picture in
            ReviewPicture(
                revision: 0, interval: picture.interval,
                samples: picture.samples.map {
                    ReviewPicture.Sample(frame: $0.frame, luma: $0.luma, spread: $0.spread, change: $0.change, peak: $0.peak)
                },
                cuts: [:])
        }
    }

    /// Shots between the cuts: index, at/atSeconds, duration/seconds (source frames at the picture's rate),
    /// cutDifference into the shot (or added), motion as in `review.shots`, and mean luma, spread, sharpness and
    /// colourfulness of the samples inside.
    func shotsJSON(_ cuts: [ListedCut]) -> (shots: [JSONValue], lengths: [Double]) {
        guard let picture, let review = reviewPicture, picture.frames > 0 else { return ([], []) }
        let fps = picture.fps
        let starts = [ListedCut(frame: 0, score: nil)] + cuts
        let ends = cuts.map(\.frame) + [picture.frames]
        var shots: [JSONValue] = []
        var lengths: [Double] = []
        for (index, (start, end)) in zip(starts, ends).enumerated() where end > start.frame {
            let duration = end - start.frame
            lengths.append(Double(duration) / fps)
            var row: [String: JSONValue] = [
                "index": .integer(index), "at": .integer(start.frame),
                "atSeconds": .number(Self.rounded(Double(start.frame) / fps)), "duration": .integer(duration),
                "seconds": .number(Self.rounded(Double(duration) / fps)),
                "motion": ReviewShots.motion(review, from: start.frame, to: end),
            ]
            if index > 0 { row[start.score == nil ? "cutAdded" : "cutDifference"] = start.score.map(Self.number) ?? .bool(true) }
            let inside = picture.samples.filter { $0.frame >= start.frame && $0.frame < end }
            if !inside.isEmpty {
                let mean = { (value: (Sample) -> Double) in Self.number(inside.map(value).reduce(0, +) / Double(inside.count)) }
                row["picture"] = .object([
                    "luma": mean(\.luma), "spread": mean(\.spread), "sharpness": mean(\.sharpness),
                    "colourfulness": mean(\.colourfulness), "samples": .integer(inside.count),
                ])
            }
            shots.append(.object(row))
        }
        return (shots, lengths)
    }

    /// Shot lengths counted in bins of 0–0.5, 0.5–1, 1–2, 2–4, 4–8, 8–16 and 16+ seconds.
    static func histogram(_ lengths: [Double]) -> JSONValue {
        let edges: [Double] = [0, 0.5, 1, 2, 4, 8, 16]
        return .array(edges.enumerated().map { index, low in
            let high = index + 1 < edges.count ? edges[index + 1] : Double.infinity
            let count = lengths.filter { $0 >= low && $0 < high }.count
            var bin: [String: JSONValue] = ["from": .number(low), "count": .integer(count)]
            if high.isFinite { bin["to"] = .number(high) }
            return .object(bin)
        })
    }

    /// Cuts in each 10-second window of the file.
    static func cutCurve(_ cuts: [ListedCut], fps: Double, seconds: Double) -> JSONValue {
        let windows = max(1, Int((seconds / 10).rounded(.up)))
        var counts = [Int](repeating: 0, count: windows)
        for cut in cuts { counts[min(windows - 1, Int(Double(cut.frame) / fps / 10))] += 1 }
        return .array(counts.enumerated().map { index, count in
            .object(["from": .integer(index * 10), "to": .integer(min(Int(seconds.rounded(.up)), index * 10 + 10)),
                     "cuts": .integer(count)])
        })
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
    static func number(_ value: Double) -> JSONValue { .number((value * 100_000).rounded() / 100_000) }
}
