import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// The home view of a library panel (D5): Recent (this project), Favorites (this Mac), then one section per pack with
/// two rows of tiles and "See all n ›"; and the matches view a search, a chip or "See all" switches to.
extension LibraryItemsSection {
    /// The home view shows while nothing narrows the list.
    var showsHome: Bool { !filter.wrappedValue.isActive && !items.isEmpty }

    @ViewBuilder var homeSections: some View {
        ForEach(LibraryHome.sections(items: items, favorites: favorites, recent: recent)) { section in
            let folded = collapsed.contains(section.id)
            let limit = tileLimit(for: section)
            VStack(alignment: .leading, spacing: 4) {
                LibraryHomeHeader(
                    title: section.kind.title, count: section.items.count, collapsed: folded,
                    seesAll: section.items.count > limit,
                    toggle: { if folded { collapsed.remove(section.id) } else { collapsed.insert(section.id) } },
                    seeAll: { seeAll(section) })
                if !folded { grid(Array(section.items.prefix(limit)), fromOnePack: true) }
            }
        }
    }

    /// Matches of the search, chips and filters, one page at a time; the plugin packs keep their header here.
    @ViewBuilder var results: some View {
        let matches = visibleItems
        let page = Array(matches.prefix(shown))
        if filter.wrappedValue.collection != nil || filter.wrappedValue.pack != nil || filter.wrappedValue.scope != nil {
            Button { leaveList() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    listTitle.font(.caption.weight(.semibold)).lineLimit(1)
                    Text(verbatim: "\(matches.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Back to all")
        }
        grid(page.filter { $0.scope != .plugin }, fromOnePack: filter.wrappedValue.pack != nil)
        // Plugin packs (#81), under the name of the plugin that ships them.
        ForEach(pluginGroups(page), id: \.plugin) { group in
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(verbatim: ([group.name] + group.packs).joined(separator: " · ")).lineLimit(1)
                } icon: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .font(.caption).foregroundStyle(.secondary)
                .help("From a plugin: read-only; Duplicate & Edit… saves your own copy")
                grid(group.items, fromOnePack: true)
            }
        }
        if matches.count > page.count {
            Button("Show \(min(Self.pageSize, matches.count - page.count)) more of \(matches.count - page.count)") {
                shown += Self.pageSize
            }
            .buttonStyle(.link).font(.caption)
        }
        if matches.isEmpty {
            Text(filter.wrappedValue.isActive ? "No matching items." : "Nothing in this library yet.")
                .font(.caption).foregroundStyle(.secondary)
            if !filter.wrappedValue.query.isEmpty, canSearchOnline {
                Button("Search online", systemImage: "globe") { searchOnline() }.font(.caption)
            }
        }
    }

    // MARK: Chips

    /// All, Mine, Packs (with counts) and Online, which opens the plugin search.
    var sourceChips: some View {
        let current = filter.wrappedValue
        let mine = items.filter { LibrarySource.mine.contains($0.scope) }.count
        return LibraryChipFlow {
            LibraryChip(title: "All", count: items.count, selected: current.source == nil) {
                filter.wrappedValue.source = nil
                filter.wrappedValue.collection = nil
                filter.wrappedValue.pack = nil
                filter.wrappedValue.scope = nil
            }
            LibraryChip(title: "Mine", count: mine, selected: current.source == LibrarySource.mine.rawValue) {
                choose(.mine)
            }
            LibraryChip(title: "Packs", count: items.count - mine, selected: current.source == LibrarySource.packs.rawValue) {
                choose(.packs)
            }
            if canSearchOnline {
                LibraryChip(title: "Online", symbol: "globe", selected: false) { searchOnline() }
                    .help("Search a plugin's source for items to add to the library")
            }
        }
    }

    private func choose(_ source: LibrarySource) {
        filter.wrappedValue.source = source.rawValue
        filter.wrappedValue.collection = nil
        filter.wrappedValue.pack = nil
        filter.wrappedValue.scope = nil
    }

    // MARK: Online

    var canSearchOnline: Bool { !document.libraryProviders(PluginAPI.librarySearch, kinds: kinds).isEmpty }

    /// Opens the plugin search with the panel's search text.
    func searchOnline() {
        document.beginLibrarySearch(PluginAPI.librarySearch, kinds: kinds)
        document.ui.librarySearch?.text = filter.wrappedValue.query
    }

    // MARK: Lists

    /// What Recent, Favorites and the packs show before "See all": two rows.
    func tileLimit(for section: LibraryHomeSection) -> Int { max(4, 2 * tilesPerRow) }

    /// The tiles in a row: the fixed columns, or as many adaptive ones as the panel's width holds.
    private var tilesPerRow: Int {
        let columns = gridColumns
        guard columns.count == 1, case .adaptive(let minimum, _) = columns[0].size else { return columns.count }
        let panel = document.ui.libraryWide
            ? LibraryPanelMetrics.wideWidth - LibraryPanelMetrics.sidebarWidth : EditorLayout.libraryWidth(document.ui)
        return max(1, Int((panel - 28) / (minimum + 8)))
    }

    private func seeAll(_ section: LibraryHomeSection) {
        switch section.kind {
        case .recent: filter.wrappedValue.collection = "recent"
        case .favorites: filter.wrappedValue.collection = "favorites"
        case .pack(let name): filter.wrappedValue.pack = name
        case .scope(let scope): filter.wrappedValue.scope = scope.rawValue
        }
    }

    private func leaveList() {
        filter.wrappedValue.collection = nil
        filter.wrappedValue.pack = nil
        filter.wrappedValue.scope = nil
    }

    private var listTitle: Text {
        let current = filter.wrappedValue
        if let collection = current.collection { return (collection == "recent" ? LibraryHomeSection.Kind.recent : .favorites).title }
        if let pack = current.pack { return Text(verbatim: pack) }
        return Text(verbatim: current.scope.flatMap(LibraryScope.init(rawValue:)).map(ProjectDocument.scopeTitle) ?? "")
    }

    /// The matches of the search and filters; a list (Recent, Favorites) keeps its own order.
    var visibleItems: [LibraryItem] {
        let filter = filter.wrappedValue
        let match = LibraryCatalog.Filter(
            tag: filter.tag, scope: filter.scope.flatMap(LibraryScope.init(rawValue:)), pack: filter.pack,
            query: filter.query.isEmpty ? nil : filter.query)
        var matches = items.filter(match.matches)
        if let source = filter.source.flatMap(LibrarySource.init(rawValue:)) {
            matches = matches.filter { source.contains($0.scope) }
        }
        switch filter.collection {
        case "recent": return Self.ordered(matches, by: recent)
        case "favorites": return Self.ordered(matches, by: favorites.reversed())
        default: return matches
        }
    }

    /// The items whose reference is in `references`, in that order.
    static func ordered(_ items: [LibraryItem], by references: [String]) -> [LibraryItem] {
        let byReference = Dictionary(items.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        return references.compactMap { byReference[$0] }
    }
}

extension LibraryHomeSection.Kind {
    /// The section's header: Recent and Favorites are UI strings; a pack's name is the user's.
    @MainActor var title: Text {
        switch self {
        case .recent: Text("Recent")
        case .favorites: Text("Favorites")
        case .pack(let name): Text(verbatim: name)
        case .scope(let scope): Text(verbatim: ProjectDocument.scopeTitle(scope))
        }
    }
}

// MARK: Tile size, grid or list, and the wide panel (P1-10)

extension LibraryItemsSection {
    /// The panel's own columns, or (for panels with a tile layout) a grid sized by the footer's slider, or one column.
    var gridColumns: [GridItem] {
        guard document.ui.libraryTab.hasTileLayout else { return columns }
        let layout = document.libraryLayout(panel)
        return layout.isList ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: layout.tileMinimum))]
    }

    /// Text styles, effects, looks and transitions have rows without a picture; in a grid they get a picture tile
    /// with the name under it. Stickers and clips already draw one, and keep their own tile in either layout.
    private var usesPictureTiles: Bool {
        document.ui.libraryTab.hasTileLayout && !document.libraryLayout(panel).isList
            && [.textPreset, .effectPreset, .look, .transitionPreset].contains(kinds.first)
    }

    @ViewBuilder func shownTile(_ item: LibraryItem) -> some View {
        if usesPictureTiles {
            LibraryPictureTile(document: document, item: item) { usePrimary(item) }
        } else {
            tile(item)
        }
    }

    /// The tile's click: place the item, or use it on the selected item (a look with nothing selected is an adjustment).
    private func usePrimary(_ item: LibraryItem) {
        switch item.kind {
        case .effectPreset, .transitionPreset: document.applyFromLibrary(item)
        case .look: if document.selected == nil { document.placeFromLibrary(item) } else { document.applyFromLibrary(item) }
        default: document.placeFromLibrary(item)
        }
    }

    /// The "+" on hover places at the playhead; effects and transitions need a clip, and sounds have their own button.
    func canPlaceFromTile(_ item: LibraryItem) -> Bool {
        guard document.fileURL != nil, !badgesInTile else { return false }
        return [.textPreset, .sticker, .look, .clip].contains(item.kind)
    }

    /// The wide panel's categories.
    var sidebar: some View {
        let sections = LibraryHome.sections(items: items, favorites: favorites, recent: recent)
        return LibraryCategorySidebar(
            sections: sections, filter: filter.wrappedValue,
            select: { section in
                filter.wrappedValue = LibraryPanelFilter(query: filter.wrappedValue.query)
                guard let section else { return }
                switch section.kind {
                case .recent: filter.wrappedValue.collection = "recent"
                case .favorites: filter.wrappedValue.collection = "favorites"
                case .pack(let name): filter.wrappedValue.pack = name
                case .scope(let scope): filter.wrappedValue.scope = scope.rawValue
                }
            },
            selectMine: {
                filter.wrappedValue = LibraryPanelFilter(query: filter.wrappedValue.query)
                filter.wrappedValue.source = LibrarySource.mine.rawValue
            },
            mineCount: items.filter { LibrarySource.mine.contains($0.scope) }.count)
    }
}
