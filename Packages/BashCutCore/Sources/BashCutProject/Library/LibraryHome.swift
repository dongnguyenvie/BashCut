import Foundation

/// One section of a library panel's home view: Recent, Favorites, or the items of one pack.
public struct LibraryHomeSection: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case recent
        case favorites
        /// A named pack.
        case pack(String)
        /// Items with no pack, together by where they live (this project, this Mac, a plugin, built in).
        case scope(LibraryScope)
    }

    public let kind: Kind
    /// Every item of the section; the view draws the first rows and offers "See all n".
    public var items: [LibraryItem]

    public init(kind: Kind, items: [LibraryItem]) {
        self.kind = kind
        self.items = items
    }

    public var id: String {
        switch kind {
        case .recent: "recent"
        case .favorites: "favorites"
        case .pack(let name): "pack:" + name.lowercased()
        case .scope(let scope): "scope:" + scope.rawValue
        }
    }
}

/// The home view of a library panel (D5): Recent, then Favorites, then the packs. Saved items (project, this Mac) come
/// before the read-only packs that ship with BashCut or a plugin, so what the user made is never buried.
public enum LibraryHome {
    /// How many items Recent and Favorites list on the home view before "See all".
    public static let shortListLimit = 8

    /// `items` are the panel's items; `favorites` and `recent` are references (`scope:id`), the latter newest first.
    /// A reference with no item in `items` (another panel's, or removed) is skipped; an empty section is left out.
    public static func sections(items: [LibraryItem], favorites: [String], recent: [String]) -> [LibraryHomeSection] {
        let byReference = Dictionary(items.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        var sections: [LibraryHomeSection] = []
        let recentItems = recent.compactMap { byReference[$0] }
        if !recentItems.isEmpty { sections.append(LibraryHomeSection(kind: .recent, items: recentItems)) }
        // Newest star first.
        let starred = favorites.reversed().compactMap { byReference[$0] }
        if !starred.isEmpty { sections.append(LibraryHomeSection(kind: .favorites, items: starred)) }
        return sections + packSections(items)
    }

    /// The packs in order of first appearance, saved ones first.
    public static func packSections(_ items: [LibraryItem]) -> [LibraryHomeSection] {
        var order: [String] = []
        var groups: [String: LibraryHomeSection] = [:]
        for item in items {
            let kind = group(of: item)
            let probe = LibraryHomeSection(kind: kind, items: [])
            if groups[probe.id] == nil {
                order.append(probe.id)
                groups[probe.id] = probe
            }
            groups[probe.id]?.items.append(item)
        }
        let all = order.compactMap { groups[$0] }
        let saved = all.filter { $0.items.contains { $0.scope.isWritable } }
        return saved + all.filter { section in !saved.contains { $0.id == section.id } }
    }

    static func group(of item: LibraryItem) -> LibraryHomeSection.Kind {
        if let pack = item.pack?.trimmingCharacters(in: .whitespaces), !pack.isEmpty { return .pack(pack) }
        return .scope(item.scope)
    }

    /// The items a "See all" of a pack section lists: the pack, compared without case.
    public static func matches(_ item: LibraryItem, pack: String) -> Bool {
        item.pack?.caseInsensitiveCompare(pack) == .orderedSame
    }
}

/// The source chips under the search field (D5): All, Mine (this project and this Mac) and Packs (built in and plugin).
/// Online is not a filter: it opens the plugin search.
public enum LibrarySource: String, CaseIterable, Sendable {
    case mine
    case packs

    public func contains(_ scope: LibraryScope) -> Bool {
        switch self {
        case .mine: scope.isWritable
        case .packs: !scope.isWritable
        }
    }
}
