import Foundation

// Adjustment layers work like adjustment layers in CapCut or Premiere: an item on one has no media or text,
// and its `color` (exposure, contrast, saturation, LUT) applies to everything stacked below it while it is
// on screen. Style kits are one-shot recipes built from them: applying a kit is one undoable edit that leaves
// ordinary items behind, with no project-wide setting.

extension Track {
    public var isAdjustment: Bool { kind == TrackKind.adjustment }
}

extension Item {
    /// An adjustment item covering `[at, at + duration)` with a color grade.
    public static func adjustment(
        id: String = UUID().uuidString, at: Int, duration: Int, color: [String: JSONValue] = [:]
    ) -> Item {
        var item = Item(id: id, at: at, duration: duration)
        item["color"] = .object(color)
        return item
    }

    /// What an adjustment item shows on the timeline: its style kit, its LUT, its look, or "Adjustment".
    /// Built-in kit and look titles are English UI strings for the caller to localize; LUT names and custom
    /// titles are user content.
    public func adjustmentTitle(in project: Project) -> String {
        if let kit = fields["styleKit"]?.string.flatMap(project.styleKit) { return kit.title }
        var color = fields["color"]?.object ?? [:]
        if let lut = color["lut"]?.string, let entry = project.colorLUTs.first(where: { $0.id == lut }) {
            return entry.name
        }
        color["lut"] = nil
        color["lutStrength"] = nil
        return project.looks.first { !$0.color.isEmpty && $0.color == color }?.title ?? "Adjustment"
    }
}

extension Project {
    /// The last frame of anything other than adjustment items: what a full-length grade should cover.
    public var contentDuration: Int {
        tracks.filter { !$0.isAdjustment }.flatMap(\.items).map(\.end).max() ?? 0
    }

    /// Operations that apply `kit`: drop the adjustment items an earlier kit added, grade the whole video,
    /// and give the kit's preset to every caption that has no preset or another kit's caption preset.
    public func styleKitOperations(_ kit: StyleKit, itemID: String = UUID().uuidString) throws -> [EditOperation] {
        let duration = contentDuration
        guard duration > 0 else { throw ProjectError.invalid("Add clips before applying a style kit") }
        guard let look = look(kit.lookID) else { throw ProjectError.invalid("Unknown look: \(kit.lookID)") }
        var planner = LayerPlanner(self)
        let previous = tracks.filter(\.isAdjustment).flatMap(\.items).filter { $0["styleKit"] != nil }
        try planner.add(previous.map { .delete(item: $0.id, ripple: false) })
        var item = Item.adjustment(id: itemID, at: 0, duration: duration, color: look.color)
        item["styleKit"] = .string(kit.id)
        try planner.placeAdjustment(item)
        let captionPresets = Set(styleKits.map(\.captionPreset))
        let captions = tracks.filter { $0.kind == TrackKind.text && $0.role == TrackRole.captions }.flatMap(\.items)
            .filter { $0.textPreset.map(captionPresets.contains) ?? true }
        try planner.add(
            captions.filter { $0.textPreset != kit.captionPreset }.map {
                .setProperties(item: $0.id, patch: ["textPreset": .string(kit.captionPreset)])
            })
        return planner.operations
    }
}

extension LayerPlanner {
    /// Places an adjustment item on the first adjustment layer, adding one above the video layers when the
    /// project has none, and spilling onto a free or new adjustment layer when the range is taken.
    @discardableResult
    public mutating func placeAdjustment(_ item: Item, on trackID: String? = nil) throws -> String {
        if let trackID { return try place(item, on: trackID) }
        if let existing = project.tracks.first(where: \.isAdjustment) { return try place(item, on: existing.id) }
        let kind = TrackKind.adjustment
        var track = Track(id: project.newTrackID(kind: kind), kind: kind, role: TrackRole.adjustment)
        track.name = "Adjustment 1"
        try add([.addTrack(track: track, atIndex: project.defaultTrackIndex(kind: kind))])
        return try place(item, on: track.id)
    }
}
