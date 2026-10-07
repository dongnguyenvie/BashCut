import Foundation

// Adjustment layers work like adjustment layers in CapCut or Premiere: an item on one has no media or text,
// and its `color` (exposure, contrast, saturation, LUT) applies to everything stacked below it while it is
// on screen. There is no project-wide grade setting.

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

    /// What an adjustment item shows on the timeline: its LUT, the built-in library look with its grade, or
    /// "Adjustment". Built-in look titles are English UI strings for the caller to localize; LUT names are user
    /// content.
    public func adjustmentTitle(in project: Project) -> String {
        var color = fields["color"]?.object ?? [:]
        if let lut = color["lut"]?.string, let entry = project.colorLUTs.first(where: { $0.id == lut }) {
            return entry.name
        }
        color["lut"] = nil
        color["lutStrength"] = nil
        guard !color.isEmpty else { return "Adjustment" }
        return LibraryBuiltIns.looks.first { $0.params["color"]?.object == color }?.name ?? "Adjustment"
    }
}

extension Project {
    /// The last frame of anything other than adjustment items: what a full-length grade should cover.
    public var contentDuration: Int {
        tracks.filter { !$0.isAdjustment }.flatMap(\.items).map(\.end).max() ?? 0
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
