import Foundation

// Adjustment layers work like adjustment layers in CapCut or Premiere: an item on one has no media or text,
// and its `color` (exposure, contrast, saturation, LUT) applies to everything stacked below it while it is
// on screen. Style kits are one-shot recipes built from them: applying a kit is one undoable edit that leaves
// ordinary items behind, with no project-wide setting.

extension Track {
    public static let adjustmentKind = "adjustment"
    public var isAdjustment: Bool { kind == Self.adjustmentKind }
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
    /// Kit and look titles are English UI strings for the caller to localize; LUT names are user content.
    public func adjustmentTitle(luts: [ColorLUT]) -> String {
        if let kit = fields["styleKit"]?.string.flatMap(StyleKit.named) { return kit.title }
        var color = fields["color"]?.object ?? [:]
        if let lut = color["lut"]?.string, let entry = luts.first(where: { $0.id == lut }) { return entry.name }
        color["lut"] = nil
        color["lutStrength"] = nil
        return ColorLook.all.first { !$0.color.isEmpty && $0.color == color }?.title ?? "Adjustment"
    }
}

/// A named color grade offered in the Filters library and used by style kits.
public struct ColorLook: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let color: [String: JSONValue]

    public static let all: [ColorLook] = [
        .init(id: "original", title: "Original", color: [:]),
        .init(id: "vivid", title: "Vivid", color: ["saturation": .number(1.2), "contrast": .number(1.05)]),
        .init(id: "muted-film", title: "Muted film", color: ["saturation": .number(0.8), "contrast": .number(0.9)]),
        .init(id: "black-white", title: "Black & white", color: ["saturation": .integer(0)]),
    ]

    public static func named(_ id: String) -> ColorLook? { all.first { $0.id == id } }
}

/// A one-shot style recipe: a full-length adjustment item with a look, plus a caption preset for every
/// caption. Applying a kit again replaces the adjustment item the previous kit added. Titles, place cards and
/// other non-caption presets keep their style.
public struct StyleKit: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let lookID: String
    public let captionStyle: String

    public static let all: [StyleKit] = [
        .init(id: "food-review", title: "Food review", lookID: "vivid", captionStyle: "bold-outline"),
        .init(id: "cinematic", title: "Cinematic", lookID: "muted-film", captionStyle: "cinematic-serif"),
    ]

    public static func named(_ id: String) -> StyleKit? { all.first { $0.id == id } }
    public var look: ColorLook { ColorLook.named(lookID) ?? ColorLook.all[0] }
}

extension Project {
    /// The last frame of anything other than adjustment items: what a full-length grade should cover.
    public var contentDuration: Int {
        tracks.filter { !$0.isAdjustment }.flatMap(\.items).map(\.end).max() ?? 0
    }

    /// Operations that apply `kit`: drop the adjustment items an earlier kit added, grade the whole video,
    /// and give the kit's preset to every caption that has no style or another kit's caption preset.
    public func styleKitOperations(_ kit: StyleKit, itemID: String = UUID().uuidString) throws -> [EditOperation] {
        let duration = contentDuration
        guard duration > 0 else { throw ProjectError.invalid("Add clips before applying a style kit") }
        var planner = LayerPlanner(self)
        let previous = tracks.filter(\.isAdjustment).flatMap(\.items).filter { $0["styleKit"] != nil }
        try planner.add(previous.map { .delete(item: $0.id, ripple: false) })
        var item = Item.adjustment(id: itemID, at: 0, duration: duration, color: kit.look.color)
        item["styleKit"] = .string(kit.id)
        try planner.placeAdjustment(item)
        let captionStyles = Set(StyleKit.all.map(\.captionStyle))
        let captions = tracks.filter { $0.kind == "text" && $0.role == TrackRole.captions }.flatMap(\.items)
            .filter { $0["style"]?.string.map(captionStyles.contains) ?? true }
        try planner.add(
            captions.filter { $0["style"]?.string != kit.captionStyle }.map {
                .setProperties(item: $0.id, patch: ["style": .string(kit.captionStyle)])
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
        let kind = Track.adjustmentKind
        var track = Track(id: project.newTrackID(kind: kind), kind: kind, role: TrackRole.adjustment)
        track.name = "Adjustment 1"
        try add([.addTrack(track: track, atIndex: project.defaultTrackIndex(kind: kind))])
        return try place(item, on: track.id)
    }
}
