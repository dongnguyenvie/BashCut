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
        tracks[track].items[index] = item
        try shift(track: track, from: original.end, by: item.duration - original.duration)
        return item.duration
    }
}
