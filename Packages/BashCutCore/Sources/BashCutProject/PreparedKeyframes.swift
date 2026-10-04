import Foundation

/// Immutable interpolation data prepared once for render-time lookup. Supports arbitrary seek order.
public struct PreparedKeyframes: Sendable {
    private struct Segment: Sendable {
        let start: Double
        let end: Double
        let reciprocalDuration: Double
        let value: Double
        let delta: Double
        let ease: ItemMotion.Ease
    }

    private let segments: [Segment]
    private let first: Double
    private let last: Double

    /// Keys use the same validated, increasing frame order as `ItemMotion`.
    public init(_ keys: [ItemMotion.Key], fallback: Double) {
        first = keys.first?.value ?? fallback
        last = keys.last?.value ?? fallback
        segments = zip(keys, keys.dropFirst()).map { from, to in
            Segment(start: Double(from.frame), end: Double(to.frame),
                    reciprocalDuration: 1 / Double(to.frame - from.frame), value: from.value,
                    delta: to.value - from.value, ease: from.ease)
        }
    }

    public func value(at frame: Double) -> Double {
        guard let firstSegment = segments.first, frame > firstSegment.start else { return first }
        guard let lastSegment = segments.last, frame < lastSegment.end else { return last }
        // Upper bound on segment end: an exact key uses that key's outgoing easing, including hold.
        var low = 0, high = segments.count
        while low < high {
            let middle = low + (high - low) / 2
            if frame < segments[middle].end { high = middle } else { low = middle + 1 }
        }
        let segment = segments[low]
        let progress = (frame - segment.start) * segment.reciprocalDuration
        return segment.value + segment.delta * segment.ease.apply(progress)
    }
}
