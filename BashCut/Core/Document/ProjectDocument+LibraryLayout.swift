import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// The library panel's width, wide mode and per-panel tile size and grid or list (P1-10).
extension ProjectDocument {
    /// Drags the panel to `width` (clamped to `LibraryPanelMetrics.widthRange`); `remember: false` while the pointer
    /// is still moving, so Settings is written once, when it is let go.
    func setLibraryWidth(_ width: Double, remember: Bool = true) {
        let width = LibraryPanelMetrics.clamp(width)
        if width != ui.libraryWidth { ui.libraryWidth = width }
        if remember, settings.libraryPanelWidth != width { settings.libraryPanelWidth = width }
    }

    /// An effect or transition dropped on the timeline is used on the clip under the pointer (on the layer it is over,
    /// or any), else on the selected item: they change an item, so they have no place of their own.
    func applyDroppedLibraryItem(_ item: LibraryItem, at frame: Int, overTrack trackID: String?) async throws {
        let under = project.tracks.filter { trackID == nil || $0.id == trackID }.flatMap(\.items)
            .first { $0.at <= frame && frame < $0.end }
        guard let target = under?.id ?? selectedID else {
            throw RPCFailure(-32602, String(localized: "Drop \(item.name) on a clip"))
        }
        try await applyLibraryItem(item, to: target)
    }

    /// The layout of the open panel (or of `panel`).
    func libraryLayout(_ panel: String? = nil) -> LibraryPanelLayout {
        ui.libraryLayouts[panel ?? ui.libraryTab.panelName] ?? LibraryPanelLayout()
    }

    func setLibraryLayout(_ layout: LibraryPanelLayout, panel: String? = nil) {
        let panel = panel ?? ui.libraryTab.panelName
        guard ui.libraryLayouts[panel] != layout else { return }
        ui.libraryLayouts[panel] = layout
        settings.libraryPanelLayouts = ui.libraryLayouts
    }

    /// `ui view --library-width --library-wide --library-layout --library-tile-size`.
    func updateLibraryLayout(_ arguments: CommandArguments) {
        if let width = arguments.optionalDouble("libraryWidth") { setLibraryWidth(width) }
        if let wide = arguments.optionalBool("libraryWide") {
            ui.libraryWide = wide
            if wide { ui.showLibraryPanel = true }
        }
        var layout = libraryLayout()
        if let mode = arguments.optionalString("libraryLayout") { layout.isList = mode == "list" }
        if let size = arguments.optionalDouble("libraryTileSize") { layout = LibraryPanelLayout(tileSize: size, isList: layout.isList) }
        setLibraryLayout(layout)
    }

    /// The `libraryLayout` of the view state: the width (0 when it is the screen's default), wide mode, and the open
    /// panel's grid or list and tile size.
    func libraryLayoutJSON() -> [String: JSONValue] {
        let layout = libraryLayout()
        return [
            "width": .number(ui.libraryWide ? LibraryPanelMetrics.wideWidth : (ui.libraryWidth ?? 0)),
            "wide": .bool(ui.libraryWide),
            "mode": .string(layout.isList ? "list" : "grid"), "tileSize": .number(layout.tileSize),
        ]
    }
}
