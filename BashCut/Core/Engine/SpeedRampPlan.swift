@preconcurrency import AVFoundation
import BashCutProject

/// Linear source-time pieces approximate the quadratic integral of each linear speed span.
/// The largest source-position error is bounded by a quarter of a source frame (plus time rounding).
struct SpeedRampPlan {
    struct Piece {
        let source: CMTimeRange
        let target: CMTimeRange
    }
    let pieces: [Piece]

    init(curve: SpeedCurve, item: Item, mediaFPS: FrameRate, fps: FrameRate) {
        let scale: CMTimeScale = 600_000
        func time(_ seconds: Double) -> CMTime { CMTime(value: CMTimeValue((seconds * Double(scale)).rounded()), timescale: scale) }
        let duration = Double(item.duration) / fps.value
        let sourceStart = Double(item.sourceIn) / mediaFPS.value
        let targetStart = Double(item.at) / fps.value
        let tolerance = 0.25 / mediaFPS.value
        var pieces: [Piece] = []
        for (start, end) in zip(curve.points, curve.points.dropFirst()) {
            let seconds = (end.t - start.t) * duration
            // Midpoint error for one chord of an integrated linear speed curve is |dv| * dt / 8.
            let count = max(1, Int(ceil(sqrt(abs(end.speed - start.speed) * seconds / (8 * tolerance)))))
            for index in 0..<count {
                let from = start.t + (end.t - start.t) * Double(index) / Double(count)
                let to = start.t + (end.t - start.t) * Double(index + 1) / Double(count)
                let source = CMTimeRange(
                    start: time(sourceStart + curve.integral(to: from) * duration),
                    end: time(sourceStart + curve.integral(to: to) * duration))
                let target = CMTimeRange(start: time(targetStart + from * duration), end: time(targetStart + to * duration))
                if source.duration > .zero, target.duration > .zero { pieces.append(Piece(source: source, target: target)) }
            }
        }
        self.pieces = pieces
    }

    func insert(from source: AVAssetTrack, into target: AVMutableCompositionTrack) throws {
        for piece in pieces {
            try target.insertTimeRange(piece.source, of: source, at: piece.target.start)
            target.scaleTimeRange(CMTimeRange(start: piece.target.start, duration: piece.source.duration), toDuration: piece.target.duration)
        }
    }
}

/// Reuse a plan for both audio/video and across edits; discard entries for removed clips on each build.
struct SpeedRampPlans {
    private struct Key: Equatable {
        let curve: SpeedCurve
        let at: Int
        let duration: Int
        let sourceIn: Int
        let mediaFPS: FrameRate
        let fps: FrameRate
    }
    private var entries: [String: (key: Key, plan: SpeedRampPlan)] = [:]
    private(set) var builds = 0

    mutating func retain(_ ids: Set<String>) { entries = entries.filter { ids.contains($0.key) } }

    mutating func plan(for item: Item, mediaFPS: FrameRate, fps: FrameRate) -> SpeedRampPlan? {
        guard let curve = item.speedCurve else { entries.removeValue(forKey: item.id); return nil }
        let key = Key(curve: curve, at: item.at, duration: item.duration, sourceIn: item.sourceIn, mediaFPS: mediaFPS, fps: fps)
        if let entry = entries[item.id], entry.key == key { return entry.plan }
        let plan = SpeedRampPlan(curve: curve, item: item, mediaFPS: mediaFPS, fps: fps)
        entries[item.id] = (key, plan)
        builds += 1
        return plan
    }
}
