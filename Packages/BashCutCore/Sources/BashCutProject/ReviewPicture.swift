import Foundation

/// Picture measurements of the composited timeline at `revision` (`review.measure`): samples at a fixed interval and
/// the difference across each hard cut on Main. Values are fractions of full scale (0…1) on a small grey thumbnail.
public struct ReviewPicture: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public let frame: Int
        /// Mean brightness.
        public let luma: Double
        /// Standard deviation of brightness: near zero on an empty (flat) frame.
        public let spread: Double
        /// Mean absolute difference from the previous sample; the first sample has 1.
        public let change: Double
        /// The largest difference of one thumbnail cell from the previous sample: a small moving part (a mouth, a
        /// ticker) shows here while the mean barely moves.
        public let peak: Double

        public init(frame: Int, luma: Double, spread: Double, change: Double, peak: Double? = nil) {
            self.frame = frame
            self.luma = luma
            self.spread = spread
            self.change = change
            self.peak = peak ?? change
        }

        /// The same picture as the previous sample: no change overall and no part that moved.
        public var isStill: Bool { change < ReviewPicture.stillChange && peak < ReviewPicture.stillPeak }
    }

    public let revision: Int
    /// Timeline frames between samples.
    public let interval: Int
    public let samples: [Sample]
    /// Mean absolute difference between the last frame before a hard cut and the first after it, by the ID of the
    /// item after the cut.
    public let cuts: [String: Double]

    public init(revision: Int, interval: Int, samples: [Sample], cuts: [String: Double]) {
        self.revision = revision
        self.interval = max(1, interval)
        self.samples = samples
        self.cuts = cuts
    }

    /// Brightness below which a flat frame counts as black, and the spread under which a frame is flat.
    public static let blackLuma = 0.06
    public static let flatSpread = 0.03
    /// A change below this between samples is the same picture (encoder noise stays well under it).
    public static let stillChange = 0.004
    /// A cell changing by more than this (about 8 of 255 levels) is movement, not encoder noise.
    public static let stillPeak = 0.03
    /// A cut whose two sides differ less than this looks like a jump cut.
    public static let jumpCutChange = 0.06

    public func isBlack(_ sample: Sample) -> Bool { sample.luma < Self.blackLuma && sample.spread < Self.flatSpread }

    /// The timeline cuts the sampler measures: adjacent items on Main without a transition between them, keyed by the
    /// item after the cut, with the frame before and the frame at the cut.
    public static func hardCuts(_ project: Project) -> [(item: String, before: Int, at: Int)] {
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let blended = Set(project.transitions.map { $0.fromItemID + "→" + $0.toItemID })
        return zip(main, main.dropFirst()).compactMap { left, right in
            guard right.at == left.end, right.at > 0, !blended.contains(left.id + "→" + right.id) else { return nil }
            return (right.id, right.at - 1, right.at)
        }
    }
}
