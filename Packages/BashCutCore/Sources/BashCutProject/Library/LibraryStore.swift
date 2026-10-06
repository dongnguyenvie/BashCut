import CryptoKit
import Foundation

/// The library items of one writable scope, in `<root>/library.json`, with their files under `<root>/files/<id>/v<N>/`.
/// The user scope lives in `~/Library/Application Support/BashCut/Library`, the project scope in
/// `<project>/.bashcut/library`. Use counts are in `<root>/usage.json`, so counting a use never rewrites the items:
/// the project store counts its own items, the user store counts everything else. Each stored file's SHA-256 is
/// kept in `fileSHA256` when the file is copied in.
public struct LibraryStore: Sendable {
    public static let format = 1
    public static let maximumItems = 5_000
    public static let maximumFileBytes: Int64 = 1 << 30

    public let root: URL
    public let scope: LibraryScope

    public init(root: URL, scope: LibraryScope) {
        precondition(scope.isWritable, "Only user and project libraries are stored")
        self.root = root
        self.scope = scope
    }

    /// The user library under an Application Support folder.
    public static func user(applicationSupport: URL) -> LibraryStore {
        LibraryStore(root: applicationSupport.appendingPathComponent("BashCut/Library", isDirectory: true), scope: .user)
    }

    /// The project library inside a project folder.
    public static func project(root: URL) -> LibraryStore {
        LibraryStore(root: root.appendingPathComponent(".bashcut/library", isDirectory: true), scope: .project)
    }

    public var file: URL { root.appendingPathComponent("library.json") }
    public var usageFile: URL { root.appendingPathComponent("usage.json") }

    /// The stored document; unknown top-level fields round-trip.
    public struct Contents: Sendable, Equatable {
        public var fields: [String: JSONValue]

        public var items: [LibraryItem] {
            get { (fields["items"]?.array ?? []).map { LibraryItem(fields: $0.object) } }
            set { fields["items"] = .array(newValue.map { .object($0.fields) }) }
        }

        /// Use counts that older versions kept in `library.json`; moved to `usage.json` on the next save.
        public var usage: [String: LibraryUsage] {
            get { (fields["usage"]?.object ?? [:]).mapValues(LibraryUsage.init(json:)) }
            set { fields["usage"] = .object(newValue.mapValues(\.json)) }
        }
    }

    public func load() throws -> Contents {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Contents(fields: ["format": .integer(Self.format), "items": .array([])])
        }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        } catch {
            throw ProjectError.invalid("\(file.path) is not valid JSON: \(error.localizedDescription)")
        }
        guard case .object(let fields) = value else { throw ProjectError.invalid("\(file.path): expected an object") }
        if let format = fields["format"]?.int, format > Self.format {
            throw ProjectError.invalid("\(file.path) was written by a newer BashCut (format \(format)); update BashCut")
        }
        return Contents(fields: fields)
    }

    /// The items, each with this scope set.
    public func items() throws -> [LibraryItem] {
        try load().items.map { LibraryItem(fields: $0.fields, scope: scope) }
    }

    func save(_ contents: Contents) throws {
        var contents = contents
        contents.fields["format"] = .integer(Self.format)
        guard contents.items.count <= Self.maximumItems else {
            throw ProjectError.invalid("A library holds at most \(Self.maximumItems) items")
        }
        if contents.fields["usage"] != nil {
            if !FileManager.default.fileExists(atPath: usageFile.path) { try saveUsage(contents.usage) }
            contents.fields["usage"] = nil
        }
        try write(.object(contents.fields), to: file)
    }

    private func write(_ value: JSONValue, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    // MARK: Changes

    /// Adds a new item. `file` and `preview` are copied in. The id must be new in this scope.
    @discardableResult
    public func add(_ item: LibraryItem, file: URL? = nil, preview: URL? = nil, now: Date = Date()) throws -> LibraryItem {
        var contents = try load()
        guard !contents.items.contains(where: { $0.id == item.id }) else {
            throw ProjectError.invalid(
                "The \(scope.rawValue) library already has \(item.id); use library update to save a new version")
        }
        var item = item
        item.scope = scope
        item["version"] = .integer(1)
        item["history"] = nil
        item["fileSHA256"] = nil
        item["createdAt"] = .string(Self.timestamp(now))
        item["updatedAt"] = .string(Self.timestamp(now))
        let copied = try copyFiles(into: &item, file: file, preview: preview)
        do {
            try item.validate(root: root)
            contents.items.append(item)
            try save(contents)
        } catch {
            copied.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        return item
    }

    /// Saves a new version of a stored item: the current one moves to `history` (the newest
    /// `LibraryItem.maximumHistory` are kept). `changes` replaces fields; a null value removes one.
    @discardableResult
    public func update(
        _ id: String, changes: [String: JSONValue], file: URL? = nil, preview: URL? = nil, now: Date = Date()
    ) throws -> LibraryItem {
        var contents = try load()
        var items = contents.items
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("The \(scope.rawValue) library has no item \(id)")
        }
        let current = items[index]
        var item = current
        item.scope = scope
        for (key, value) in changes where !Self.managedKeys.contains(key) {
            item[key] = value == .null ? nil : value
        }
        var previous = current.fields
        previous["history"] = nil
        item["history"] = .array(Array((current.history + [.object(previous)]).suffix(LibraryItem.maximumHistory)))
        item["version"] = .integer(current.version + 1)
        item["updatedAt"] = .string(Self.timestamp(now))
        let copied = try copyFiles(into: &item, file: file, preview: preview)
        do {
            try item.validate(root: root)
            guard item.kind == current.kind else { throw ProjectError.invalid("library item \(id): kind cannot change") }
            items[index] = item
            contents.items = items
            try save(contents)
        } catch {
            copied.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        return item
    }

    /// Removes an item, its files and its usage.
    @discardableResult
    public func remove(_ id: String) throws -> LibraryItem {
        var contents = try load()
        var items = contents.items
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("The \(scope.rawValue) library has no item \(id)")
        }
        let removed = LibraryItem(fields: items.remove(at: index).fields, scope: scope)
        contents.items = items
        try save(contents)
        var usage = try usage()
        if usage.removeValue(forKey: removed.reference) != nil { try saveUsage(usage) }
        try? FileManager.default.removeItem(at: filesFolder(removed.id))
        return removed
    }

    /// Adds an item another scope stored, as it is (versions, dates and creator kept), with its files folder.
    @discardableResult
    func adopt(_ item: LibraryItem, from source: LibraryStore) throws -> LibraryItem {
        var contents = try load()
        guard !contents.items.contains(where: { $0.id == item.id }) else {
            throw ProjectError.invalid("The \(scope.rawValue) library already has \(item.id)")
        }
        let manager = FileManager.default
        let from = source.filesFolder(item.id)
        let to = filesFolder(item.id)
        let copied = manager.fileExists(atPath: from.path)
        if copied {
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: to.path) { try manager.removeItem(at: to) }
            try manager.copyItem(at: from, to: to)
        }
        let adopted = LibraryItem(fields: item.fields, scope: scope)
        do {
            try adopted.validate(root: root)
            contents.items.append(adopted)
            try save(contents)
        } catch {
            if copied { try? manager.removeItem(at: to) }
            throw error
        }
        return adopted
    }

    // MARK: Usage

    /// Counts one use of the item `reference` (`scope:id`). Only `usage.json` is rewritten.
    public func recordUse(_ reference: String, now: Date = Date()) throws {
        var usage = try usage()
        var entry = usage[reference] ?? LibraryUsage()
        entry.count += 1
        entry.lastUsed = Self.timestamp(now)
        usage[reference] = entry
        try saveUsage(usage)
    }

    /// Use counts by reference, from `usage.json`, or from `library.json` for a library older versions wrote.
    public func usage() throws -> [String: LibraryUsage] {
        guard FileManager.default.fileExists(atPath: usageFile.path) else { return try load().usage }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: usageFile))
        } catch {
            throw ProjectError.invalid("\(usageFile.path) is not valid JSON: \(error.localizedDescription)")
        }
        return (value.object["usage"]?.object ?? [:]).mapValues(LibraryUsage.init(json:))
    }

    /// Sets the use count of `reference`, as when an item moves here from another scope.
    func setUsage(_ reference: String, _ entry: LibraryUsage) throws {
        var usage = try usage()
        usage[reference] = entry
        try saveUsage(usage)
    }

    private func saveUsage(_ usage: [String: LibraryUsage]) throws {
        try write(.object(["format": .integer(Self.format), "usage": .object(usage.mapValues(\.json))]), to: usageFile)
    }

    // MARK: Files

    /// Fields the store sets itself; changes cannot write them.
    static let managedKeys: Set<String> = [
        "id", "version", "history", "createdAt", "updatedAt", "file", "preview", "fileSHA256",
    ]

    public func url(of path: String) -> URL { root.appendingPathComponent(path) }

    func filesFolder(_ id: String) -> URL { root.appendingPathComponent("files/\(id)", isDirectory: true) }

    /// Copies `file` and `preview` into `files/<id>/v<version>/` and points the item at them. Returns what was copied.
    private func copyFiles(into item: inout LibraryItem, file: URL?, preview: URL?) throws -> [URL] {
        var copied: [URL] = []
        let folder = filesFolder(item.id).appendingPathComponent("v\(item.version)", isDirectory: true)
        for (key, source) in [("file", file), ("preview", preview)] {
            guard let source else { continue }
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            do {
                try Self.copy(source, to: destination)
            } catch {
                copied.forEach { try? FileManager.default.removeItem(at: $0) }
                throw error
            }
            copied.append(destination)
            item[key] = .string("files/\(item.id)/v\(item.version)/\(source.lastPathComponent)")
            if key == "file" {
                do {
                    item["fileSHA256"] = .string(try Self.sha256(of: destination))
                } catch {
                    copied.forEach { try? FileManager.default.removeItem(at: $0) }
                    throw error
                }
            }
        }
        return copied
    }

    /// The SHA-256 of a file as lowercase hex, read in 1 MB chunks.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copies a regular file up to `maximumFileBytes`, replacing an earlier copy at `destination`.
    static func copy(_ source: URL, to destination: URL) throws {
        let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { throw ProjectError.invalid("No file at \(source.path)") }
        guard Int64(values?.fileSize ?? 0) <= maximumFileBytes else {
            throw ProjectError.invalid("\(source.lastPathComponent) is larger than 1 GB")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.copyItem(at: source, to: destination)
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
