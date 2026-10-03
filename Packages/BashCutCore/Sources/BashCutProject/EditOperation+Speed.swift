import Foundation

/// `setSpeed`: constant speed for a clip and its linked partner. By default the clip keeps the same source and its
/// timeline duration changes (2× halves it), rippling later clips on its layers; with `keepDuration` it keeps its
/// length and uses more or less source. Either way it is shortened to fit the source if needed.
extension Project {
    mutating func applySpeed(_ id: String, speed: Double, keepDuration: Bool) throws {
        let linked = try linkedItemID(id)
        let duration = try speedItem(id: id, speed: speed, keepDuration: keepDuration, duration: nil)
        // The partner gets the same speed and length so picture and sound stay in sync.
        if let linked { _ = try speedItem(id: linked, speed: speed, keepDuration: true, duration: duration) }
    }

    public static let speedRange: ClosedRange<Double> = 0.1...16

    /// Sets an item's speed and new duration (or `duration` for a linked partner), rippling later items on its
    /// layer by the change. Returns the new duration.
    mutating func speedItem(id: String, speed: Double, keepDuration: Bool, duration forced: Int?) throws -> Int {
        guard speed.isFinite, Self.speedRange.contains(speed) else {
            throw ProjectError.invalid("Speed must be between 0.1× and 16×")
        }
        let (track, index) = try location(id)
        let original = tracks[track].items[index]
        guard let asset = media.first(where: { $0.id == original.mediaID }) else {
            throw ProjectError.invalid("Speed applies to clips with media")
        }
        guard original.fields["freezeFrame"] == nil else {
            throw ProjectError.invalid("A freeze frame has no speed; remove the freeze first")
        }
        let wanted = forced ?? (keepDuration
            ? original.duration
            : max(1, Int((Double(original.duration) * original.speed / speed).rounded())))
        // Frames the remaining source can fill at this speed.
        let available = Double(asset.frames - original.sourceIn) / asset.fps.value * fps.value / speed
        let fitting = Int((available + 0.0001).rounded(.down))
        guard fitting >= 1 else { throw ProjectError.invalid("Not enough source left for \(speed)× speed") }
        var item = original
        item.duration = min(wanted, fitting)
        item.fields["speed"] = speed == 1 ? nil : .number(speed)
        // A constant speed replaces a ramp; setSpeedCurve puts its curve back right after.
        item.fields["speedCurve"] = nil
        tracks[track].items[index] = item
        try shift(track: track, from: original.end, by: item.duration - original.duration)
        return item.duration
    }
}

/// `setSpeedCurve`: a speed ramp for a clip and its linked partner, or none (back to constant speed at the
/// curve's average). Like `setSpeed`, the clip keeps its source and its length follows the average speed, unless
/// `keepDuration`.
extension Project {
    mutating func applySpeedCurve(_ id: String, curve: SpeedCurve?, keepDuration: Bool) throws {
        let linked = try linkedItemID(id)
        guard let curve else {
            let (track, index) = try location(id)
            // Removing a ramp keeps the clip as it is, at its average speed.
            tracks[track].items[index].fields["speedCurve"] = nil
            if let linked {
                let (linkedTrack, linkedIndex) = try location(linked)
                tracks[linkedTrack].items[linkedIndex].fields["speedCurve"] = nil
            }
            return
        }
        let duration = try speedItem(id: id, speed: curve.average, keepDuration: keepDuration, duration: nil)
        try setCurve(id, curve)
        if let linked {
            _ = try speedItem(id: linked, speed: curve.average, keepDuration: true, duration: duration)
            try setCurve(linked, curve)
        }
    }

    private mutating func setCurve(_ id: String, _ curve: SpeedCurve) throws {
        let (track, index) = try location(id)
        tracks[track].items[index].setSpeedCurve(curve)
    }

    /// `setSource`: points a clip and its linked partner at other media (a reversed copy) and in-point, recording
    /// `reversed` (or clearing it with nil) so the change can be undone by reversing again.
    mutating func applySource(_ id: String, media mediaID: String, sourceIn: Int, reversed: JSONValue?) throws {
        guard let asset = media.first(where: { $0.id == mediaID }) else { throw ProjectError.invalid("Unknown media \(mediaID)") }
        guard sourceIn >= 0, sourceIn < asset.frames else { throw ProjectError.invalid("Invalid source in-point") }
        let linked = try linkedItemID(id)
        for itemID in [id] + (linked.map { [$0] } ?? []) {
            let (track, index) = try location(itemID)
            guard tracks[track].items[index].mediaID != nil else {
                throw ProjectError.invalid("Only clips with media can change their source")
            }
            tracks[track].items[index].fields["media"] = .string(mediaID)
            tracks[track].items[index].sourceIn = sourceIn
            tracks[track].items[index].fields["reversed"] = reversed
        }
    }
}

extension SpeedCurve {
    /// The ramp after moving the clip's `edge` by `frames` (positive moves it later): a shorter clip keeps its part
    /// of the ramp, a longer one holds the end speed over what was added, so the ramp stays on the same source.
    func trimmed(edge: Edge, by frames: Int, duration: Int) -> SpeedCurve {
        let old = Double(duration)
        // The kept range in fractions of the old clip.
        let start = edge == .start ? Double(frames) / old : 0
        let end = edge == .end ? 1 + Double(frames) / old : 1
        var next = self
        if start > 0 || end < 1 { next = next.cut(from: max(0, start), to: min(1, end)) }
        let kept = min(1, end) - max(0, start)
        if start < 0 || end > 1 { next = next.extended(before: max(0, -start) / kept, after: max(0, end - 1) / kept) }
        return next
    }
}

extension Item {
    /// Stores a ramp and its average as `speed` (1 is left implicit, as `setSpeed` does).
    mutating func setSpeedCurve(_ curve: SpeedCurve) {
        fields["speedCurve"] = curve.json
        let average = curve.average
        fields["speed"] = abs(average - 1) < 1e-9 ? nil : .number(average)
    }
}
