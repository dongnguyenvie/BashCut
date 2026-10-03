import Foundation

/// A speed ramp (CapCut's "Curve"): speed changes along the clip instead of staying constant.
///
/// Stored on an item as `speedCurve: [{"t": 0, "speed": 1}, …]`: `t` is the position in the clip's timeline
/// duration (0 at its start, 1 at its end) and `speed` the source seconds played per timeline second there, linear
/// between points. The item's `speed` holds the curve's average, so everything that only needs how much source
/// the clip uses (validation, trims, interchange) keeps working; source positions inside the clip come from
/// `sourceFraction(at:)`.
public struct SpeedCurve: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let t: Double
        public let speed: Double

        public init(t: Double, speed: Double) {
            self.t = t
            self.speed = speed
        }
    }

    public static let maximumPoints = 16
    public let points: [Point]

    /// Checks the points: 2–16, `t` rising strictly from 0 to 1, every speed within `Project.speedRange`.
    public init(_ points: [Point]) throws {
        guard (2...Self.maximumPoints).contains(points.count) else {
            throw ProjectError.invalid("A speed curve needs 2 to \(Self.maximumPoints) points")
        }
        guard points.first?.t == 0, points.last?.t == 1,
            zip(points, points.dropFirst()).allSatisfy({ $0.t < $1.t }), points.allSatisfy({ $0.t.isFinite })
        else { throw ProjectError.invalid("Speed curve points must run from t 0 to t 1 in increasing order") }
        guard points.allSatisfy({ $0.speed.isFinite && Project.speedRange.contains($0.speed) }) else {
            throw ProjectError.invalid("Speed curve speeds must be between 0.1× and 16×")
        }
        self.points = points
    }

    public init(json: JSONValue) throws {
        guard case .array(let array) = json else { throw ProjectError.invalid("speedCurve must be an array of points") }
        try self.init(array.map { value in
            let object = value.object
            guard let t = object["t"]?.double, let speed = object["speed"]?.double else {
                throw ProjectError.invalid("Each speed curve point needs t and speed")
            }
            return Point(t: t, speed: speed)
        })
    }

    public var json: JSONValue {
        .array(points.map { .object(["t": .number(Self.rounded($0.t)), "speed": .number(Self.rounded($0.speed))]) })
    }

    /// Speed at position `t` (0…1), linear between points.
    public func speed(at t: Double) -> Double {
        let t = min(1, max(0, t))
        guard let upper = points.firstIndex(where: { $0.t >= t }) else { return points[points.count - 1].speed }
        guard upper > 0 else { return points[0].speed }
        let a = points[upper - 1], b = points[upper]
        return a.speed + (b.speed - a.speed) * (t - a.t) / (b.t - a.t)
    }

    /// ∫ speed dt from `from` to `to` (fractions of the clip): source time per unit of clip time, so source
    /// seconds = this × the clip's timeline seconds.
    public func integral(from: Double = 0, to: Double) -> Double {
        let lower = min(1, max(0, min(from, to))), upper = min(1, max(0, max(from, to)))
        guard upper > lower else { return 0 }
        let cuts = [lower] + points.map(\.t).filter { $0 > lower && $0 < upper } + [upper]
        let total = zip(cuts, cuts.dropFirst()).reduce(0.0) { sum, span in
            sum + (span.1 - span.0) * (speed(at: span.0) + speed(at: span.1)) / 2
        }
        return from <= to ? total : -total
    }

    /// Average speed: source seconds per timeline second over the whole clip.
    public var average: Double { integral(to: 1) }

    /// Fraction of the clip's source used up to timeline position `t`.
    public func sourceFraction(at t: Double) -> Double { integral(to: t) / average }

    /// The part between `from` and `to`, stretched back to 0…1 (a split or trim keeps each part's ramp).
    public func cut(from: Double, to: Double) -> SpeedCurve {
        let lower = min(1, max(0, from)), upper = min(1, max(0, to))
        guard upper > lower else { return self }
        let inner = points.filter { $0.t > lower && $0.t < upper }
        let span = upper - lower
        let stretched = [Point(t: 0, speed: speed(at: lower))]
            + inner.map { Point(t: ($0.t - lower) / span, speed: $0.speed) }
            + [Point(t: 1, speed: speed(at: upper))]
        return (try? SpeedCurve(Self.merged(stretched))) ?? self
    }

    /// The curve for a clip lengthened by `before` and `after` fractions of its old duration, holding the first
    /// and last speeds over the added parts.
    public func extended(before: Double, after: Double) -> SpeedCurve {
        let before = max(0, before), after = max(0, after)
        guard before > 0 || after > 0 else { return self }
        let total = 1 + before + after
        var result: [Point] = []
        if before > 0 { result.append(Point(t: 0, speed: points[0].speed)) }
        result += points.map { Point(t: (before + $0.t) / total, speed: $0.speed) }
        if after > 0 { result.append(Point(t: 1, speed: points[points.count - 1].speed)) }
        return (try? SpeedCurve(Self.merged(result))) ?? self
    }

    /// Drops points too close to the one before (keeps the last), so a cut never makes a zero-length segment.
    static func merged(_ points: [Point]) -> [Point] {
        var result: [Point] = []
        for point in points {
            if let last = result.last, point.t - last.t < 1e-6 {
                result[result.count - 1] = Point(t: point.t == 1 ? 1 : last.t, speed: point.speed)
            } else {
                result.append(point)
            }
        }
        if result.count > maximumPoints {
            // Keep the ends and the evenly spaced middle.
            let step = Double(result.count - 1) / Double(maximumPoints - 1)
            result = (0..<maximumPoints).map { result[Int((Double($0) * step).rounded())] }
        }
        return result
    }

    private static func rounded(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

    /// CapCut-style presets.
    public static let presets: [(id: String, title: String, points: [(Double, Double)])] = [
        ("montage", "Montage", [(0, 1), (0.2, 2.5), (0.5, 0.6), (0.8, 2.5), (1, 1)]),
        ("hero", "Hero time", [(0, 2), (0.35, 2), (0.5, 0.3), (0.65, 2), (1, 2)]),
        ("bullet", "Bullet time", [(0, 2.5), (0.4, 0.25), (0.6, 0.25), (1, 2.5)]),
        ("jump-cut", "Jump cut", [(0, 1), (0.4, 1), (0.5, 5), (0.6, 1), (1, 1)]),
        ("flash-in", "Flash in", [(0, 5), (0.3, 1), (1, 1)]),
        ("flash-out", "Flash out", [(0, 1), (0.7, 1), (1, 5)]),
    ]

    public static func preset(_ id: String) -> SpeedCurve? {
        presets.first { $0.id == id }.flatMap { preset in
            try? SpeedCurve(preset.points.map { Point(t: $0.0, speed: $0.1) })
        }
    }
}

extension Item {
    /// The item's speed ramp, if it has a valid one.
    public var speedCurve: SpeedCurve? { fields["speedCurve"].flatMap { try? SpeedCurve(json: $0) } }

    /// Timeline frames into the clip where the source is `seconds` past its start (the inverse of
    /// `sourceSeconds(afterFrames:fps:)` inside the clip), not rounded.
    public func timelineFrames(atSourceSeconds seconds: Double, fps: FrameRate) -> Double {
        guard let curve = speedCurve, duration > 0 else { return seconds / speed * fps.value }
        let clipSeconds = Double(duration) / fps.value
        let target = seconds / clipSeconds
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if curve.integral(to: middle) < target { low = middle } else { high = middle }
        }
        return (low + high) / 2 * Double(duration)
    }

    /// Source seconds from the clip's source start to `frames` timeline frames into the clip.
    public func sourceSeconds(afterFrames frames: Int, fps: FrameRate) -> Double {
        let seconds = Double(frames) / fps.value
        guard let curve = speedCurve, duration > 0 else { return seconds * speed }
        let clipSeconds = Double(duration) / fps.value
        let t = Double(frames) / Double(duration)
        if t <= 1, t >= 0 { return curve.integral(to: t) * clipSeconds }
        // Outside the clip (an extending trim): the end speeds continue.
        return t < 0 ? seconds * curve.points[0].speed
            : curve.integral(to: 1) * clipSeconds + (seconds - clipSeconds) * curve.points[curve.points.count - 1].speed
    }
}
