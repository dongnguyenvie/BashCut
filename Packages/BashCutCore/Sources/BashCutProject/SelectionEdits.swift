import Foundation

/// Edits on several selected timeline items at once. Each returns operations for one undo step; linked picture and
/// sound count once, because the core edit already carries the partner along.
public enum SelectionEdits {
    /// The selected items that still exist, in timeline order, without the linked partner of an item already listed.
    /// When both halves of a linked pair are selected the picture stands for them, since deleting only the sound
    /// keeps the picture.
    public static func roots(_ ids: [String], in project: Project) -> [Item] {
        let wanted = Set(ids)
        let items = project.tracks.flatMap(\.items).filter { wanted.contains($0.id) }
            .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        var covered = Set<String>()
        return items.filter { item in
            if let video = item["linkedVideo"]?.string, wanted.contains(video), items.contains(where: { $0.id == video }) {
                return false
            }
            guard !covered.contains(item.id) else { return false }
            covered.insert(item.id)
            if let linked = item.linkedItemID { covered.insert(linked) }
            return true
        }
    }

    /// Deletes every selected item (rippling or leaving gaps).
    public static func delete(_ ids: [String], ripple: Bool, in project: Project) -> [EditOperation] {
        roots(ids, in: project).map { .delete(item: $0.id, ripple: ripple) }
    }

    /// Mutes every selected clip with sound, or unmutes them all when every one is already muted.
    public static func toggleMute(_ ids: [String], in project: Project) -> [EditOperation] {
        let wanted = Set(ids)
        let targets = project.tracks.filter { $0.kind == "audio" || $0.kind == "video" }
            .flatMap(\.items).filter { wanted.contains($0.id) && $0.mediaID != nil }
        let mute = !targets.allSatisfy { $0["muted"] == .bool(true) }
        return targets.map { .setProperties(item: $0.id, patch: ["muted": .bool(mute)]) }
    }

    /// Whether `toggleMute` would unmute: every selected clip with sound is muted.
    public static func allMuted(_ ids: [String], in project: Project) -> Bool {
        let wanted = Set(ids)
        let targets = project.tracks.flatMap(\.items).filter { wanted.contains($0.id) && $0.mediaID != nil }
        return !targets.isEmpty && targets.allSatisfy { $0["muted"] == .bool(true) }
    }

    /// Moves every selected item `delta` frames along its own layer, keeping their offsets. Items on a magnetic layer
    /// stay (that layer packs its clips), and an item that would land on another clip spills onto a free layer like a
    /// single move. Items are moved front first in the direction of travel, so they never land on each other.
    public static func shift(_ ids: [String], by delta: Int, in project: Project) throws -> [EditOperation] {
        guard delta != 0 else { return [] }
        let movable = roots(ids, in: project).compactMap { item -> (Item, Track)? in
            guard let track = project.tracks.first(where: { $0.items.contains { $0.id == item.id } }), !track.magnetic
            else { return nil }
            return (item, track)
        }
        guard let earliest = movable.map(\.0.at).min(), earliest + delta >= 0 else {
            if movable.isEmpty { return [] }
            throw ProjectError.invalid("Clips cannot move before the start of the timeline")
        }
        var planner = LayerPlanner(project)
        for (item, track) in movable.sorted(by: { delta > 0 ? $0.0.at > $1.0.at : $0.0.at < $1.0.at }) {
            try planner.move(item.id, to: track.id, at: item.at + delta)
        }
        return planner.operations
    }

    /// Items between `anchor` and `target` on `target`'s layer, both included (Shift-click). Only `target` when the
    /// anchor is on another layer or gone.
    public static func range(from anchor: String?, to target: String, in project: Project) -> [String] {
        guard let track = project.tracks.first(where: { $0.items.contains { $0.id == target } }),
            let end = track.items.first(where: { $0.id == target })
        else { return [] }
        guard let anchor, let start = track.items.first(where: { $0.id == anchor }) else { return [target] }
        let lower = min(start.at, end.at), upper = max(start.at, end.at)
        return track.items.filter { $0.at >= lower && $0.at <= upper }.sorted { $0.at < $1.at }.map(\.id)
    }

    /// Every item on the timeline, in timeline order (Select All).
    public static func all(in project: Project) -> [String] {
        project.tracks.flatMap(\.items).sorted { ($0.at, $0.id) < ($1.at, $1.id) }.map(\.id)
    }
}

/// Clips copied from the timeline: each item with its layer and its offset from the earliest copied item.
public struct TimelineClipboard: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let item: Item
        public let trackID: String
        public let trackKind: String
        public let offset: Int
    }

    public let entries: [Entry]

    /// Copies the selected items and their linked partners, so pasted picture keeps its sound.
    public init?(copying ids: [String], from project: Project) {
        var wanted = Set(ids)
        for item in project.tracks.flatMap(\.items) where wanted.contains(item.id) {
            if let linked = item.linkedItemID { wanted.insert(linked) }
        }
        let copied = project.tracks.flatMap { track in
            track.items.filter { wanted.contains($0.id) }.map { (item: $0, track: track) }
        }
        guard let start = copied.map(\.item.at).min() else { return nil }
        entries = copied.sorted { ($0.item.at, $0.item.id) < ($1.item.at, $1.item.id) }.map {
            Entry(item: $0.item, trackID: $0.track.id, trackKind: $0.track.kind, offset: $0.item.at - start)
        }
    }

    /// Operations that paste the clips at `frame` with new IDs, each on its old layer (or the first layer of the same
    /// kind when that one is gone), spilling onto a free layer where clips are in the way. Linked pairs are linked
    /// again. Returns the new IDs in clipboard order.
    public func paste(at frame: Int, in project: Project) throws -> (operations: [EditOperation], ids: [String]) {
        var planner = LayerPlanner(project)
        var newIDs: [String: String] = [:]
        var ids: [String] = []
        for entry in entries {
            guard entry.item.mediaID.map({ id in project.media.contains { $0.id == id } }) ?? true else { continue }
            guard let track = project.track(id: entry.trackID)
                ?? project.tracks.first(where: { $0.kind == entry.trackKind })
            else { continue }
            var item = entry.item
            let id = UUID().uuidString
            item.fields["id"] = .string(id)
            item.fields["linkedAudio"] = nil
            item.fields["linkedVideo"] = nil
            item.at = frame + entry.offset
            try planner.place(item, on: track.id)
            newIDs[entry.item.id] = id
            ids.append(id)
        }
        for entry in entries {
            guard let videoID = newIDs[entry.item.id], let audio = entry.item.fields["linkedAudio"]?.string,
                let audioID = newIDs[audio]
            else { continue }
            try planner.add([.setLinkedAudio(video: videoID, audio: audioID)])
        }
        guard !ids.isEmpty else { throw ProjectError.invalid("Nothing to paste: the copied clips' media is gone") }
        return (planner.operations, ids)
    }
}
