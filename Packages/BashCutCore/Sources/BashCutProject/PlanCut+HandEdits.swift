import Foundation

/// Speed and music edits made by hand on what an apply built, which a later apply puts back on the rebuilt items with
/// the same ID: a constant speed or a ramp on a clip (`clip speed`, `clip speed-curve`), and the span of a music bed
/// trimmed or extended by hand. Built items record what the build itself set (`planAudio`, `planSpeed`,
/// `planMusic`), so a later apply tells a hand edit from the list's own value; sound and picture fields are merged
/// with the build's record (`planBuilt`, PlanCut+Keep).
extension PlanCut {
    /// The sound fields the build set on an item, as `{field: value}`.
    static let audioTag = "planAudio"
    /// The constant speed the list gave a clip.
    static let speedTag = "planSpeed"
    /// The span the build gave the music bed: `{at, dur, in, media}`.
    static let musicTag = "planMusic"
    static let audioKeys = ["volumeDb", "muted", "fadeIn", "fadeOut"]

    /// What was set by hand on built items' speed and the music bed (part of `HandSet`).
    struct HandEdits {
        /// A ramp (or, without one, the constant speed) set by hand, by clip item ID.
        var speeds: [String: (speed: Double, curve: SpeedCurve?)] = [:]
        /// The bed as it was, when its span is not the one the build gave it.
        var music: Item?

        init(_ built: [Item]) {
            for item in built where item.fields[tag] != .string("captions") {
                let speed = item["speed"]?.double ?? 1
                if let curve = item.speedCurve {
                    speeds[item.id] = (speed, curve)
                } else if abs(speed - (item[speedTag]?.double ?? 1)) > 1e-9 {
                    speeds[item.id] = (speed, nil)
                }
            }
            if let bed = built.first(where: { $0.id == "plan-music" }), let span = bed[musicTag]?.object,
                span["at"]?.int != bed.at || span["dur"]?.int != bed.duration || span["in"]?.int != bed.sourceIn
            {
                music = bed
            }
        }
    }

    /// `patch` with `planAudio` recording the sound fields in it, so a later apply tells them from hand edits.
    static func recordingAudio(_ patch: [String: JSONValue]) -> [String: JSONValue] {
        let set = patch.filter { audioKeys.contains($0.key) }
        guard !set.isEmpty else { return patch }
        return patch.merging([audioTag: .object(set)]) { $1 }
    }

    /// The speed the list or a hand edit gives clip `clip` built as `id`: the list's own speed when it gives one,
    /// else a ramp or speed set by hand on the clip before.
    static func placeSpeed(_ clip: Clip, id: String, kept: HandEdits, in planner: inout LayerPlanner) throws {
        if clip.speedGiven || clip.speed != 1 {
            if clip.speed != 1 { try planner.add([.setSpeed(item: id, speed: clip.speed, keepDuration: false)]) }
            try planner.add([.setProperties(item: id, patch: [speedTag: .number(clip.speed)])])
        } else if let hand = kept.speeds[id] {
            try planner.add([hand.curve.map { .setSpeedCurve(item: id, curve: $0, keepDuration: false) }
                ?? .setSpeed(item: id, speed: hand.speed, keepDuration: false)])
        }
    }

    /// Where the bed goes: from frame 0 for `length` frames from the list's `from`, or the span it had when it was
    /// trimmed or extended by hand and the list still plays the same music from the same point.
    static func musicSpan(
        _ music: Music, media: Media, length: Int, kept: HandEdits, fps: Double
    ) -> (at: Int, duration: Int, sourceIn: Int) {
        let sourceIn = Int((music.from * media.fps.value).rounded(.down))
        let built = (at: 0, duration: length, sourceIn: sourceIn)
        guard let bed = kept.music, let span = bed[musicTag]?.object, bed.mediaID == music.media,
            span["in"]?.int == sourceIn
        else { return built }
        let available = Int(((media.durationSeconds - Double(bed.sourceIn) / media.fps.value) * fps).rounded(.down))
        let duration = min(bed.duration, available)
        return duration > 0 ? (bed.at, duration, bed.sourceIn) : built
    }
}
