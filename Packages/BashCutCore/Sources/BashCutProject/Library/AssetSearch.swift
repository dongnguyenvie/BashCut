import Foundation

/// The "All assets" search (P2-B1, ⇧⌘F): one query over the whole local library (every kind and scope), the project's
/// media and its selects, with the matches grouped by kind. Matching ignores case and diacritics, every word of the
/// query must appear, and a match in the name ranks above one only in the pack, tags or path.
public enum AssetSearch {
    /// What a result is.
    public enum Asset: Sendable, Equatable {
        case media(Media)
        case select(ProjectSelect)
        case library(LibraryItem)
    }

    /// A section of the results, in the order they are listed.
    public enum Group: Hashable, Sendable, Identifiable {
        case media
        case selects
        case library(LibraryKind)

        /// Project media and selects first, then the library kinds, sounds before pictures and styles.
        public static let order: [Group] = [.media, .selects] + libraryOrder.map(Group.library)
        static let libraryOrder: [LibraryKind] = [
            .audio, .clip, .sticker, .textPreset, .effectPreset, .transitionPreset, .look, .voice, .brand,
        ]

        public var id: String {
            switch self {
            case .media: "media"
            case .selects: "selects"
            case .library(let kind): kind.rawValue
            }
        }
    }

    public struct Result: Sendable, Equatable, Identifiable {
        public let asset: Asset
        /// Higher is a better match: 3 the name starts with the query, 2 a word of the name starts with it, 1 the name
        /// has every word, 0 only the other fields do.
        public let score: Int

        public var id: String {
            switch asset {
            case .media(let media): "media:" + media.id
            case .select(let select): "select:" + select.id
            case .library(let item): "library:" + item.reference
            }
        }

        public var group: Group {
            switch asset {
            case .media: .media
            case .select: .selects
            // `search` skips items of an unknown kind.
            case .library(let item): .library(item.kind ?? .sticker)
            }
        }
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public let group: Group
        /// The first matches, best first; `total` counts them all.
        public let results: [Result]
        public let total: Int
        public var id: String { group.id }
    }

    /// How many results a section lists; the rest are counted.
    public static let sectionLimit = 40

    /// The sections with matches, in `Group.order`. `library` is every item of the catalog (`LibraryCatalog.items()`,
    /// project first): an id saved in several scopes is listed once, from the scope in use. An empty query finds
    /// nothing.
    public static func search(
        _ query: String, library: [LibraryItem], media: [Media], selects: [ProjectSelect], limit: Int = sectionLimit
    ) -> [Section] {
        let words = words(query)
        guard !words.isEmpty else { return [] }
        var results: [Group: [Result]] = [:]
        func add(_ asset: Asset, name: String, other: [String]) {
            guard let score = score(words, name: name, other: other) else { return }
            let result = Result(asset: asset, score: score)
            results[result.group, default: []].append(result)
        }
        for item in media {
            add(.media(item), name: item.fileName, other: [item.path, item.kind, item.fields["description"]?.string ?? ""])
        }
        let mediaNames = Dictionary(media.map { ($0.id, $0.fileName) }, uniquingKeysWith: { first, _ in first })
        for select in selects {
            add(.select(select), name: select.quote ?? "",
                other: [mediaNames[select.media] ?? "", select.reason ?? "", select.status])
        }
        var seen: Set<String> = []
        for item in library where item.kind != nil && seen.insert((item.kind?.rawValue ?? "") + ":" + item.id).inserted {
            let other = [item.id, item.pack ?? "", item.params["role"]?.string ?? "", item.createdBy["pluginName"]?.string ?? ""]
                + item.tags
            add(.library(item), name: item.name, other: other)
        }
        return Group.order.compactMap { group in
            guard let found = results[group], !found.isEmpty else { return nil }
            // Stable: equal scores keep the order they came in.
            let ranked = found.enumerated().sorted { ($1.element.score, $0.offset) < ($0.element.score, $1.offset) }.map(\.element)
            return Section(group: group, results: Array(ranked.prefix(limit)), total: ranked.count)
        }
    }

    /// The results in the order they are listed, for moving through them with the arrow keys.
    public static func flattened(_ sections: [Section]) -> [Result] { sections.flatMap(\.results) }

    /// The query's words, folded.
    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.searchFolded
    }

    /// The rank of a match, or nil when some word is in none of the fields.
    static func score(_ words: [String], name: String, other: [String]) -> Int? {
        let folded = fold(name)
        let rest = fold(other.joined(separator: " "))
        guard words.allSatisfy({ folded.contains($0) || rest.contains($0) }) else { return nil }
        guard words.allSatisfy(folded.contains) else { return 0 }
        if folded.hasPrefix(words.joined(separator: " ")) { return 3 }
        let nameWords = folded.split { !$0.isLetter && !$0.isNumber }
        return nameWords.contains { $0.hasPrefix(words[0]) } ? 2 : 1
    }
}
