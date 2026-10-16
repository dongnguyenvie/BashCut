import AppKit
import BashCutDocument
import BashCutProject
import SwiftUI

/// The edge between the library panel and the viewer: drag it to resize the panel between 300 and 520 pt (P1-10).
struct LibraryResizeHandle: View {
    @Bindable var document: ProjectDocument
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle().fill(hovering || startWidth != nil ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12))
            .frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = startWidth ?? EditorLayout.libraryWidth(document.ui)
                            startWidth = start
                            document.setLibraryWidth(start + drag.translation.width, remember: false)
                        }
                        .onEnded { _ in
                            startWidth = nil
                            document.setLibraryWidth(EditorLayout.libraryWidth(document.ui))
                        })
                    .help("Drag to resize the panel")
                    .accessibilityLabel("Resize the library panel")
            }
    }
}

/// The footer of a panel with tiles: a size slider and a grid or list switch, remembered per panel (P1-10).
struct LibraryPanelFooter: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        let layout = document.libraryLayout()
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3").font(.system(size: 9)).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { layout.tileSize },
                set: { document.setLibraryLayout(LibraryPanelLayout(tileSize: $0, isList: layout.isList)) }), in: 0...1)
                .controlSize(.mini).frame(maxWidth: 140).disabled(layout.isList)
                .help("Tile size").accessibilityLabel("Tile size")
            Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("Layout", selection: Binding(
                get: { layout.isList },
                set: { document.setLibraryLayout(LibraryPanelLayout(tileSize: layout.tileSize, isList: $0)) })
            ) {
                Image(systemName: "square.grid.2x2").tag(false).help("Grid")
                Image(systemName: "list.bullet").tag(true).help("List")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 64)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
    }
}

/// The wide panel's category sidebar (P1-10): Recent, Favorites, Mine and each pack of the open panel.
struct LibraryCategorySidebar: View {
    let sections: [LibraryHomeSection]
    let filter: LibraryPanelFilter
    let select: (LibraryHomeSection?) -> Void
    let selectMine: () -> Void
    let mineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("All", count: nil, selected: !filter.isActive) { select(nil) }
            ForEach(sections.filter { [.recent, .favorites].contains($0.kind) }) { section in
                row(section.kind.title, count: section.items.count,
                    selected: filter.collection == (section.kind == .recent ? "recent" : "favorites")) { select(section) }
            }
            row("Mine", count: mineCount, selected: filter.source == LibrarySource.mine.rawValue, action: selectMine)
            Divider().padding(.vertical, 4)
            ForEach(sections.filter { if case .pack = $0.kind { true } else { false } }) { section in
                row(section.kind.title, count: section.items.count,
                    selected: { if case .pack(let name) = section.kind { filter.pack == name } else { false } }()) { select(section) }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        row(Text(title), count: count, selected: selected, action: action)
    }

    private func row(_ title: Text, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title.lineLimit(1)
                Spacer(minLength: 4)
                if let count { Text(verbatim: "\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A tile with a picture and the name under it, for panels whose own rows have no picture (P1-10). Transition
/// presets and effect presets play their preview on hover and looks show the viewer's frame graded (P2-B3).
struct LibraryPictureTile: View {
    let document: ProjectDocument
    let item: LibraryItem
    let action: () -> Void
    @Environment(LookPreviews.self) private var lookPreviews: LookPreviews?

    var body: some View {
        PictureTile(
            caption: LibraryView.title(item), help: Text(verbatim: item.name), enabled: enabled, action: action
        ) { hovering in
            picture(hovering)
        }
    }

    @ViewBuilder private func picture(_ hovering: Bool) -> some View {
        if item.kind == .textPreset {
            TextPresetTile(item: item)
        } else if item.kind == .transitionPreset, let transition = TransitionPreviewPicture(preset: item, playing: hovering) {
            transition
        } else if item.kind == .effectPreset, let preview = document.libraryCatalog.previewURL(of: item),
                  AnimatedPreviewPicture.draws(preview) {
            AnimatedPreviewPicture(url: preview, symbol: LibraryKind.effectPreset.tileSymbol, playing: hovering)
        } else if let preview = document.libraryCatalog.previewURL(of: item) {
            LibraryImage(url: preview, fallbackSymbol: item.kind?.tileSymbol ?? "photo")
        } else if item.kind == .look {
            LookPreviewPicture(document: document, previews: lookPreviews, item: item)
        } else {
            LibraryTileFallback(symbol: item.kind?.tileSymbol ?? "photo")
        }
    }

    /// Effects and transitions change the selected item; the rest add one to the timeline.
    private var enabled: Bool {
        item.kind == .effectPreset || item.kind == .transitionPreset ? document.selected != nil : document.fileURL != nil
    }
}

/// The expand control in a panel's title: the wide panel (760 pt over the viewer, with a category sidebar). In the
/// wide panel the same button leaves it, and so does Esc.
struct LibraryWideButton: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        let wide = document.ui.libraryWide
        Button {
            document.ui.libraryWide.toggle()
        } label: {
            Image(systemName: wide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(wide ? .cancelAction : nil)
        .help(wide ? "Back to the narrow panel (Esc)" : "Widen the panel over the viewer")
        .accessibilityLabel(wide ? "Back to the narrow panel" : "Widen the panel")
    }
}

/// All assets beside a panel's search field (design section 4): the same search over every panel, project media and
/// selects as ⇧⌘F, starting from the panel's text.
struct AllAssetsButton: View {
    let document: ProjectDocument
    let query: String

    var body: some View {
        Button { document.showAssetSearch(query) } label: {
            Text("All assets").font(.caption2.weight(.medium)).lineLimit(1).fixedSize()
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Search every panel, project media and selects, grouped by kind (⇧⌘F)")
    }
}
