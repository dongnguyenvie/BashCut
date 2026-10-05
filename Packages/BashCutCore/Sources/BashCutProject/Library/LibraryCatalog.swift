import CryptoKit
import Foundation

/// Every library item the editor can use: the open project's, this Mac's, the plugins' and the built-in ones, in
/// that order of precedence when the same id is in several scopes.
public struct LibraryCatalog: Sendable {
    public var builtIn: [LibraryItem]
    /// Items plugins contribute, with the folder their paths are relative to (by plugin id in `createdBy.plugin`).
    public var plugin: [LibraryItem]
    public var pluginRoots: [String: URL]
    public let user: LibraryStore?
    public let project: LibraryStore?

    public init(
        builtIn: [LibraryItem] = LibraryBuiltIns.items, plugin: [LibraryItem] = [], pluginRoots: [String: URL] = [:],
        user: LibraryStore?, project: LibraryStore?
    ) {
        self.builtIn = builtIn.map { LibraryItem(fields: $0.fields, scope: .builtIn) }
        self.plugin = plugin.map { LibraryItem(fields: $0.fields, scope: .plugin) }
        self.pluginRoots = pluginRoots
        self.user = user
        self.project = project
    }

    /// Every item, project first, then user, plugin and built-in.
    public func items() throws -> [LibraryItem] {
        try (project?.items() ?? []) + (user?.items() ?? []) + plugin + builtIn
    }

    public func store(_ scope: LibraryScope) throws -> LibraryStore {
        switch scope {
        case .user: if let user { return user }
        case .project: if let project { return project }
        case .builtIn, .plugin: throw ProjectError.invalid("\(scope.rawValue) library items are read-only")
        }
        throw ProjectError.invalid(scope == .project ? "Open a saved project to use its library" : "No user library")
    }

    /// The item `id`, from `scope` or the first scope that has it. `id` may also be written `scope:id`.
    public func item(_ id: String, scope: LibraryScope? = nil) throws -> LibraryItem {
        var scope = scope
        var id = id
        if let colon = id.firstIndex(of: ":"), let prefix = LibraryScope(rawValue: String(id[..<colon])) {
            scope = prefix
            id = String(id[id.index(after: colon)...])
        }
        guard let item = try items().first(where: { $0.id == id && (scope == nil || $0.scope == scope) }) else {
            throw ProjectError.invalid("No library item \(id)\(scope.map { " in the \($0.rawValue) library" } ?? "")")
        }
        return item
    }

    /// The folder an item's `file` and `preview` are relative to.
    public func root(of item: LibraryItem) -> URL? {
        switch item.scope {
        case .user: user?.root
        case .project: project?.root
        case .plugin: item.createdBy["plugin"]?.string.flatMap { pluginRoots[$0] }
        case .builtIn: nil
        }
    }

    public func fileURL(of item: LibraryItem) -> URL? {
        guard let path = item.file, let root = root(of: item) else { return nil }
        return root.appendingPathComponent(path)
    }

    // MARK: Search

    /// Filters for `library list`. Every given filter must match.
    public struct Filter: Sendable {
        public var kinds: [LibraryKind]?
        public var tag: String?
        public var scope: LibraryScope?
        public var creator: String?
        public var pack: String?
        public var query: String?

        public init(
            kinds: [LibraryKind]? = nil, tag: String? = nil, scope: LibraryScope? = nil, creator: String? = nil,
            pack: String? = nil, query: String? = nil
        ) {
            self.kinds = kinds
            self.tag = tag
            self.scope = scope
            self.creator = creator
            self.pack = pack
            self.query = query
        }

        public func matches(_ item: LibraryItem) -> Bool {
            if let kinds, !kinds.contains(where: { $0 == item.kind }) { return false }
            if let tag, !item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
            if let scope, item.scope != scope { return false }
            if let creator, (item.creator ?? (item.scope == .builtIn ? "built-in" : "")) != creator { return false }
            if let pack, item.pack?.caseInsensitiveCompare(pack) != .orderedSame { return false }
            if let query, !query.isEmpty {
                let text = ([item.id, item.name, item.pack ?? ""] + item.tags).joined(separator: " ")
                if !text.localizedCaseInsensitiveContains(query) { return false }
            }
            return true
        }
    }

    public func items(matching filter: Filter) throws -> [LibraryItem] { try items().filter(filter.matches) }

    /// What a panel shows for `kinds`: each ID once (the scope in use), built-in items first in their order, then
    /// plugin, user and project ones.
    public func panelItems(_ kinds: [LibraryKind]) throws -> [LibraryItem] {
        var seen: Set<String> = []
        let inUse = try items(matching: Filter(kinds: kinds)).filter { seen.insert($0.id).inserted }
        let order: [LibraryScope] = [.builtIn, .plugin, .user, .project]
        return order.flatMap { scope in inUse.filter { $0.scope == scope } }
    }

    // MARK: Usage

    /// The store that counts uses of `item`: the project for its own items, the user library for the rest.
    func usageStore(for item: LibraryItem) -> LibraryStore? { item.scope == .project ? project : user }

    public func usage() throws -> [String: LibraryUsage] {
        try (user?.usage() ?? [:]).merging(project?.usage() ?? [:]) { $1 }
    }

    public func recordUse(_ item: LibraryItem, now: Date = Date()) throws {
        try usageStore(for: item)?.recordUse(item.reference, now: now)
    }

    // MARK: Changes

    /// Adds a new item to a writable scope. Built-in ids are reserved.
    @discardableResult
    public func add(
        _ item: LibraryItem, into scope: LibraryScope, file: URL? = nil, preview: URL? = nil, now: Date = Date()
    ) throws -> LibraryItem {
        try checkNotBuiltIn(item.id)
        return try store(scope).add(item, file: file, preview: preview, now: now)
    }

    func checkNotBuiltIn(_ id: String) throws {
        if builtIn.contains(where: { $0.id == id }) {
            throw ProjectError.invalid("\(id) is a built-in library item; choose another id")
        }
    }

    /// Saves an improved copy of any item (built-in and plugin ones included) as `newID` in `scope`: version 1,
    /// `basedOn` pointing at the original, with `changes` applied and the original's files copied unless replaced.
    @discardableResult
    public func copy(
        _ item: LibraryItem, as newID: String, into scope: LibraryScope, changes: [String: JSONValue],
        createdBy: JSONValue, file: URL? = nil, preview: URL? = nil, now: Date = Date()
    ) throws -> LibraryItem {
        let store = try store(scope)
        try checkNotBuiltIn(newID)
        var copy = LibraryItem(fields: item.fields, scope: scope)
        for key in ["history", "createdAt", "updatedAt", "file", "preview"] { copy[key] = nil }
        copy["id"] = .string(newID)
        copy["basedOn"] = .string("\(item.reference)@v\(item.version)")
        copy["createdBy"] = createdBy
        for (key, value) in changes where !LibraryStore.managedKeys.contains(key) {
            copy[key] = value == .null ? nil : value
        }
        let root = root(of: item)
        return try store.add(
            copy, file: file ?? item.file.flatMap { path in root.map { $0.appendingPathComponent(path) } },
            preview: preview ?? item.preview.flatMap { path in root.map { $0.appendingPathComponent(path) } }, now: now)
    }

    // MARK: Stats

    /// Usage per item, the stored items nobody used, and groups of items with the same kind and content.
    public func stats(kinds: [LibraryKind]? = nil) throws -> JSONValue {
        let usage = try usage()
        let items = try items().filter { kinds?.contains($0.kind ?? .voice) ?? true }
        let rows: [JSONValue] = items.map { item in
            let entry = usage[item.reference] ?? LibraryUsage()
            return .object([
                "id": .string(item.id), "scope": .string(item.scope.rawValue),
                "kind": item.kind.map { .string($0.rawValue) } ?? .null, "name": .string(item.name),
                "count": .integer(entry.count), "lastUsed": entry.lastUsed.map(JSONValue.string) ?? .null,
            ])
        }
        let unused = items.filter { $0.scope.isWritable && (usage[$0.reference]?.count ?? 0) == 0 }
        var groups: [String: [LibraryItem]] = [:]
        for item in items { groups[contentKey(item), default: []].append(item) }
        let duplicates = groups.values.filter { $0.count > 1 }
            .sorted { $0[0].reference < $1[0].reference }
            .map { group in JSONValue.array(group.map { .string($0.reference) }) }
        return .object([
            "items": .array(rows), "unused": .array(unused.map { .string($0.reference) }),
            "duplicates": .array(duplicates),
        ])
    }

    /// Kind, params and the file's SHA-256: equal keys mean the same content under different names.
    private func contentKey(_ item: LibraryItem) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let params = (try? encoder.encode(JSONValue.object(item.params))).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        let digest = fileURL(of: item).flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            .map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        return [item.kind?.rawValue ?? "", params, digest].joined(separator: "\u{1F}")
    }
}

/// The built-in packs the Text, Stickers and Effects panels show (#75). Names are English UI strings to localize;
/// IDs are stable.
public enum LibraryBuiltIns {
    public static let items: [LibraryItem] = textPresets + stickers + effects

    /// One per caption renderer preset (`TextPreset.all`), with the sample text the panel shows.
    public static let textPresets: [LibraryItem] = [
        ("bold-outline", "Bold Outline", "Quá là ngon!"),
        ("cinematic-serif", "Cinematic Serif", "a moment to remember"),
        ("keyword-sticker", "Keyword Sticker", "BEST BITE"),
        ("place-card", "Place Card", "BẾN THÀNH · QUẬN 1"),
        ("hook-title", "Hook Title", "ĂN GÌ HÔM NAY?"),
        ("chapter-card", "Chapter Card", "CHAPTER 01"),
    ].map { id, name, sample in
        LibraryItem(
            id: id, kind: .textPreset, name: name, pack: "Text styles",
            params: ["textPreset": .string(id), "text": .string(sample)])
    }

    /// Emoji stickers, placed as Bold Outline text.
    public static let stickers: [LibraryItem] = [
        ("fire", "Fire", "🔥"), ("yum", "Yum", "😋"), ("thumbs-up", "Thumbs up", "👍"), ("hundred", "Hundred", "💯"),
        ("star", "Star", "⭐"), ("pin", "Pin", "📍"), ("hot-pot", "Hot pot", "🍲"), ("laughing", "Laughing", "😂"),
    ].map { id, name, emoji in
        LibraryItem(
            id: id, kind: .sticker, name: name, pack: "Emoji",
            params: ["emoji": .string(emoji), "textPreset": .string("bold-outline")])
    }

    /// Framing presets for the selected clip.
    public static let effects: [LibraryItem] = [
        LibraryItem(
            id: "punch-in", kind: .effectPreset, name: "Punch in 1.3×", pack: "Framing",
            params: ["patch": .object(["transform": .object(["zoom": .number(1.3)])])]),
        LibraryItem(
            id: "reset-framing", kind: .effectPreset, name: "Reset framing", pack: "Framing",
            params: ["patch": .object(["transform": .object(["zoom": .number(1), "pan": .integer(0), "tilt": .integer(0)])])]),
    ]
}
