import Foundation

// The library (#66): every left-rail panel (Audio, Text, Stickers, Effects, Transitions, Filters, Voice) is a
// collection of items with one model. Items come from four scopes: built-in (shipped with the app, read-only),
// user (this Mac), project (`.bashcut/library` in the project folder, so they travel with it) and plugin (read-only,
// removed with the plugin). Improving an item saves a new version or a copy; nothing is overwritten silently.

/// What an item is, and so which panel shows it.
public enum LibraryKind: String, CaseIterable, Sendable {
    case audio
    case textPreset = "text-preset"
    case sticker
    case effectPreset = "effect-preset"
    case transitionPreset = "transition-preset"
    case look
    case voice

    /// The library panel (`CommandCatalog.libraryPanels`) that lists this kind.
    public var panel: String {
        switch self {
        case .audio: "audio"
        case .textPreset: "text"
        case .sticker: "stickers"
        case .effectPreset: "effects"
        case .transitionPreset: "transitions"
        case .look: "filters"
        case .voice: "voice"
        }
    }

    public static func kinds(inPanel panel: String) -> [LibraryKind] { allCases.filter { $0.panel == panel } }
}

/// Where an item lives. Built-in and plugin items are read-only.
public enum LibraryScope: String, CaseIterable, Sendable {
    case builtIn = "built-in"
    case user
    case project
    case plugin

    public var isWritable: Bool { self == .user || self == .project }
}

/// One library item. Unknown fields round-trip, like the project document.
///
/// Stored fields: `id`, `kind`, `name`, `tags`, `pack`, `source`, `license`, `createdBy` (`by`: user, agent or
/// plugin; `agent`, `session`, `plugin`), `version`, `createdAt`, `updatedAt`, `preview` and `file` (paths relative
/// to the scope's library folder), `params` (what the kind needs to apply or place it), `basedOn` (`scope:id@vN` of
/// the item it was copied from) and `history` (earlier versions, newest last).
public struct LibraryItem: JSONObject, Identifiable {
    public var fields: [String: JSONValue]
    /// Not stored: set when the item is read from its scope.
    public var scope: LibraryScope = .builtIn

    public init(fields: [String: JSONValue]) { self.fields = fields }

    public init(fields: [String: JSONValue], scope: LibraryScope) {
        self.fields = fields
        self.scope = scope
    }

    public init(
        id: String, kind: LibraryKind, name: String, tags: [String] = [], pack: String? = nil,
        params: [String: JSONValue] = [:], scope: LibraryScope = .builtIn
    ) {
        var fields: [String: JSONValue] = [
            "id": .string(id), "kind": .string(kind.rawValue), "name": .string(name), "version": .integer(1),
        ]
        if !tags.isEmpty { fields["tags"] = .array(tags.map(JSONValue.string)) }
        if let pack { fields["pack"] = .string(pack) }
        if !params.isEmpty { fields["params"] = .object(params) }
        self.init(fields: fields, scope: scope)
    }

    public static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.fields == rhs.fields && lhs.scope == rhs.scope
    }

    public var id: String { fields["id"]?.string ?? "" }
    public var kind: LibraryKind? { fields["kind"]?.string.flatMap(LibraryKind.init(rawValue:)) }
    public var name: String { fields["name"]?.string ?? "" }
    public var tags: [String] { fields["tags"]?.array.compactMap(\.string) ?? [] }
    public var pack: String? { fields["pack"]?.string }
    public var version: Int { fields["version"]?.int ?? 1 }
    public var params: [String: JSONValue] { fields["params"]?.object ?? [:] }
    public var file: String? { fields["file"]?.string }
    public var preview: String? { fields["preview"]?.string }
    public var createdBy: [String: JSONValue] { fields["createdBy"]?.object ?? [:] }
    /// `user`, `agent` or `plugin`; built-in items have none.
    public var creator: String? { createdBy["by"]?.string }
    public var history: [JSONValue] { fields["history"]?.array ?? [] }
    /// `scope:id`, unique across scopes; usage counts are keyed by it.
    public var reference: String { "\(scope.rawValue):\(id)" }

    /// The item as commands return it: its fields without `history`, plus `scope`, `panel` and `versions`.
    public func json(usage: LibraryUsage? = nil, includeHistory: Bool = false) -> JSONValue {
        var result = fields
        if !includeHistory { result["history"] = nil }
        result["scope"] = .string(scope.rawValue)
        result["panel"] = kind.map { .string($0.panel) } ?? .null
        result["versions"] = .integer(history.count + 1)
        if let usage { result["usage"] = usage.json }
        return .object(result)
    }

    /// The `createdBy` record for an item an author saves: the user, an agent (by name) or a plugin.
    public static func creator(author: Author, session: String? = nil, plugin: String? = nil) -> JSONValue {
        var record: [String: JSONValue]
        switch author {
        case .user: record = ["by": .string("user")]
        case .plugin: record = ["by": .string("plugin")]
        case .agent: record = ["by": .string("agent")]
        default: record = ["by": .string("agent"), "agent": .string(author.rawValue)]
        }
        if let session { record["session"] = .string(session) }
        if let plugin { record["plugin"] = .string(plugin) }
        return .object(record)
    }
}

/// How often an item was applied or placed, and when last.
public struct LibraryUsage: Sendable, Equatable {
    public var count: Int
    public var lastUsed: String?

    public init(count: Int = 0, lastUsed: String? = nil) {
        self.count = count
        self.lastUsed = lastUsed
    }

    init(json: JSONValue) {
        self.init(count: json.object["count"]?.int ?? 0, lastUsed: json.object["lastUsed"]?.string)
    }

    public var json: JSONValue {
        .object(["count": .integer(count), "lastUsed": lastUsed.map(JSONValue.string) ?? .null])
    }
}

// MARK: Validation

extension LibraryItem {
    public static let maximumTags = 32
    public static let maximumHistory = 20

    /// Checks the common fields and what the kind needs. `root` is the scope's library folder, used to check that
    /// `file` and `preview` exist; nil skips that check.
    public func validate(root: URL? = nil) throws {
        let label = "library item \(id.isEmpty ? "(no id)" : id)"
        guard id.range(of: StyleCatalog.idPattern, options: .regularExpression) != nil else {
            throw ProjectError.invalid("\(label): id must be 1–64 lowercase letters, digits or hyphens")
        }
        guard let kind else {
            let kinds = LibraryKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw ProjectError.invalid("\(label): kind must be one of \(kinds)")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, name.count <= 120 else { throw ProjectError.invalid("\(label): name must be 1–120 characters") }
        guard version >= 1 else { throw ProjectError.invalid("\(label): version must be 1 or more") }
        try validateMetadata(label: label)
        try validatePaths(root: root, label: label)
        try validateParams(kind, label: label)
    }

    private func validateMetadata(label: String) throws {
        if let tags = fields["tags"] {
            guard case .array(let values) = tags, values.count <= Self.maximumTags,
                values.allSatisfy({ ($0.string.map { !$0.isEmpty && $0.count <= 40 && !$0.contains(",") }) == true })
            else {
                throw ProjectError.invalid("\(label): tags must be at most \(Self.maximumTags) texts of 1–40 characters")
            }
        }
        for key in ["pack", "source", "license"] {
            guard let value = fields[key] else { continue }
            guard let text = value.string, text.count <= (key == "pack" ? 80 : 1_000) else {
                throw ProjectError.invalid("\(label): \(key) must be text")
            }
        }
        if let params = fields["params"], params.object.isEmpty, params != .object([:]) {
            throw ProjectError.invalid("\(label): params must be an object")
        }
    }

    private func validatePaths(root: URL?, label: String) throws {
        for key in ["file", "preview"] {
            guard let value = fields[key] else { continue }
            guard let path = value.string, Self.isSafeRelativePath(path) else {
                throw ProjectError.invalid("\(label): \(key) must be a path inside the library folder")
            }
            if let root, !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
                throw ProjectError.invalid("\(label): \(key) \(path) is missing")
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func validateParams(_ kind: LibraryKind, label: String) throws {
        switch kind {
        case .audio:
            guard file != nil else { throw ProjectError.invalid("\(label): an audio item needs a file") }
        case .sticker:
            guard file != nil || params["emoji"]?.string?.isEmpty == false else {
                throw ProjectError.invalid("\(label): a sticker needs params.emoji or a file")
            }
            if let preset = params["textPreset"], preset.string.map(TextPreset.all.contains) != true {
                throw ProjectError.invalid("\(label): params.textPreset must be one of \(TextPreset.all.joined(separator: ", "))")
            }
        case .textPreset:
            guard params["textPreset"]?.string.map(TextPreset.all.contains) == true else {
                throw ProjectError.invalid(
                    "\(label): params.textPreset must be one of \(TextPreset.all.joined(separator: ", "))")
            }
        case .effectPreset:
            // A recipe (#76): params.steps with params.parameters, or an old params.patch. Its file is its own sound.
            _ = try EffectRecipe(params: params, label: label)
        case .transitionPreset:
            // params.sfx wins over the preset's own file.
            _ = try TransitionPreset(params: params, label: label)
        case .look:
            // A filter stack (#79): params.color, and optionally a .cube file as its LUT.
            _ = try FilterStack(params: params, label: label)
            if let file, !FilterStack.isLUTFile(file) {
                throw ProjectError.invalid("\(label): a look's file must be a .cube LUT")
            }
        case .voice:
            break
        }
    }

    /// A relative path without `..`, a leading slash or a home reference.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), path.count <= 512 else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}
