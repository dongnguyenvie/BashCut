import Foundation

/// Swapping the music bed (`music replace`, P2-C3): the clips on the Music layers make way for one new sound over
/// the same span, at the old bed's level and fades, on the first bed clip's layer (so its ducking stays).
public struct MusicReplacement {
    public let planner: LayerPlanner
    public let trackID: String
    public let removed: [String]
    public let itemIDs: [String]
    public let at: Int
    public let duration: Int
    public let looped: Bool
    /// The new sound plays once and ends before the old bed did.
    public let shortened: Bool
}

extension Project {
    /// Clips on audio layers with the music role, in timeline order.
    public var musicBedItems: [(item: Item, track: Track)] {
        tracks.filter { $0.kind == TrackKind.audio && $0.role == TrackRole.music }
            .flatMap { track in track.items.map { ($0, track) } }
            .sorted { $0.item.at < $1.item.at }
    }

    /// The plan that replaces the music bed with `sound` from `fromSeconds` of it: the old clips go, the new sound
    /// covers the bed's span (from its first clip's start to its last clip's end), repeating back to back when
    /// `loop` and shorter than the span, with the first clip's `volumeDb`, `fadeIn` and `muted` and the last clip's
    /// `fadeOut`. Throws when there is no bed.
    public func musicReplacePlan(_ sound: Media, fromSeconds: Double = 0, loop: Bool = true) throws -> MusicReplacement {
        guard sound.kind == "audio" else { throw ProjectError.invalid("The new music must be an audio file") }
        let bed = musicBedItems
        guard let first = bed.first, let start = bed.map(\.item.at).min(), let end = bed.map(\.item.end).max() else {
            throw ProjectError.invalid("There is no music on a Music layer to replace; place music with media place or library place")
        }
        guard fromSeconds >= 0 else { throw ProjectError.invalid("from must be 0 or later") }
        let sourceIn = Int((fromSeconds * sound.fps.value).rounded(.down))
        let available = sound.placementFrames(in: fps)
            - Int((fromSeconds * fps.value).rounded(.up))
        guard available > 0 else { throw ProjectError.invalid("from is past the end of the new music") }
        let span = end - start
        let looped = loop && span > available
        let total = looped ? span : min(span, available)
        var items = try Project.tiledAudioItems(sound, at: start, total: total, length: available, sourceIn: sourceIn) {
            "Repeating the new music \($0) times is too many; pick a longer sound"
        }
        var planner = LayerPlanner(self)
        if !media.contains(where: { $0.id == sound.id }) { try planner.add([.addMedia(sound)]) }
        try planner.add(bed.map { .delete(item: $0.item.id, ripple: false) })
        var kept: [String: JSONValue] = [:]
        for key in ["volumeDb", "fadeIn", "muted"] { kept[key] = first.item.fields[key] }
        for index in items.indices {
            for (key, value) in kept where index == 0 || key != "fadeIn" { items[index].fields[key] = value }
        }
        if let fadeOut = bed.max(by: { $0.item.end < $1.item.end })?.item.fields["fadeOut"], let last = items.indices.last {
            items[last].fields["fadeOut"] = fadeOut
        }
        try planner.add(items.map { .insert(track: first.track.id, item: $0) })
        return MusicReplacement(
            planner: planner, trackID: first.track.id, removed: bed.map(\.item.id), itemIDs: items.map(\.id), at: start,
            duration: total, looped: looped, shortened: span > total)
    }
}
