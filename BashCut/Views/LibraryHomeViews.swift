import BashCutPlugin
import BashCutProject
import SwiftUI

/// Lays its children out in rows and wraps to the next row when the width runs out: the chips under the search field
/// (five of them do not fit one row of the narrow panel).
struct LibraryChipFlow: Layout {
    var spacing = 6.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + spacing * Double(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width = 0.0
        var height = 0.0
    }

    private func rows(in width: Double, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].indices.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(index)
        }
        return rows
    }
}

/// One chip: a pill with a label and an optional count; the selected one is filled.
struct LibraryChip: View {
    let title: LocalizedStringKey
    var count: Int?
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
                Text(title)
                if let count { Text(verbatim: "\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.caption).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What the Media panel lists (`ui view --media-source`).
enum MediaLibrarySource: String, CaseIterable, Identifiable {
    case footage
    case project
    case shared
    case selects
    case clips

    var id: Self { self }
    var title: String {
        switch self {
        case .footage: "Footage"
        case .project: "Project"
        case .shared: "Shared"
        case .selects: "Selects"
        case .clips: "Clips"
        }
    }
}

/// The Media panel's source chips with counts (they replaced a menu, which hid how much each source held).
struct MediaSourceChips: View {
    let document: ProjectDocument
    @Binding var selection: MediaLibrarySource
    /// Footage, Project and Shared media counts; Selects and Clips are counted here.
    let counts: [MediaLibrarySource: Int]
    @State private var clipCount = 0

    var body: some View {
        LibraryChipFlow {
            ForEach(MediaLibrarySource.allCases) { source in
                LibraryChip(
                    title: LocalizedStringKey(source.title), count: count(source), selected: selection == source
                ) { selection = source }
            }
        }
        .task(id: "\(document.libraryRevision):\(document.fileURL?.path ?? "")") {
            clipCount = (try? document.libraryCatalog.panelItems([.clip]).count) ?? 0
        }
    }

    private func count(_ source: MediaLibrarySource) -> Int {
        switch source {
        case .selects: document.project.selects.count
        case .clips: clipCount
        default: counts[source] ?? 0
        }
    }
}

/// A library tile with its hover star (Favorites, global) and, unless the tile draws them itself, its badges.
struct LibraryGridTile<Content: View>: View {
    let item: LibraryItem
    let isFavorite: Bool
    var showsBadges = true
    /// The whole section is one pack and its header says so: no plugin or folder mark.
    var hidesScope = false
    let toggleFavorite: () -> Void
    /// Place at the playhead, when the item can be placed (the "+" on hover).
    var place: (() -> Void)?
    /// Whether the timeline can take the item by drag.
    var draggable = true
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if showsBadges { LibraryItemBadges(item: item, hidesScope: hidesScope) }
            }
            .overlay(alignment: showsBadges ? .topLeading : .topTrailing) {
                if hovering || isFavorite {
                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 10)).foregroundStyle(isFavorite ? Color.yellow : .secondary)
                            .padding(3).background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain).padding(2)
                    .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering, let place {
                    Button(action: place) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 15))
                            .foregroundStyle(Color.accentColor, Color.black.opacity(0.5))
                    }
                    .buttonStyle(.plain).padding(3)
                    .help("Place at Playhead").accessibilityLabel("Place at Playhead")
                }
            }
            .onHover { hovering = $0 }
            .modifier(LibraryDragSource(reference: draggable ? item.reference : nil))
    }
}

/// The header of a home view section: a collapse chevron, its title and count, and "See all n ›".
struct LibraryHomeHeader: View {
    let title: Text
    let count: Int
    let collapsed: Bool
    let seesAll: Bool
    let toggle: () -> Void
    let seeAll: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .bold))
                        .frame(width: 8)
                    title.font(.caption.weight(.semibold)).lineLimit(1)
                    Text(verbatim: "\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(collapsed ? "Expand" : "Collapse")
            Spacer(minLength: 4)
            if seesAll, !collapsed {
                Button("See all \(count) ›", action: seeAll).buttonStyle(.link).font(.caption)
            }
        }
    }
}

/// The drag source of a library tile: the `bashcut-library:scope:id` string the timeline accepts (as it does from
/// plugin view grids), so an effect, sticker or sound can be dropped on a layer.
struct LibraryDragSource: ViewModifier {
    let reference: String?

    func body(content: Content) -> some View {
        if let payload = reference.flatMap(PluginViewDrag.libraryPayload) {
            content.onDrag { NSItemProvider(object: payload as NSString) }
        } else {
            content
        }
    }
}
