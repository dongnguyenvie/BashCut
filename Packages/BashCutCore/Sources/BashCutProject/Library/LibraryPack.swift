import Foundation

/// A library pack on disk: a folder (or a .zip of one) with `pack.json` — `{"format": 1, "name": "Food", "items":
/// [...]}` — and the items' files at the paths their `file` and `preview` give, relative to the folder.
public enum LibraryPack {
    public static let manifestName = "pack.json"

    /// Writes the items to a new pack folder at `folder` (which must not exist or be empty) and returns the folder.
    @discardableResult
    public static func export(
        _ items: [LibraryItem], name: String, catalog: LibraryCatalog, to folder: URL
    ) throws -> URL {
        let manager = FileManager.default
        if let existing = try? manager.contentsOfDirectory(atPath: folder.path), !existing.isEmpty {
            throw ProjectError.invalid("\(folder.path) is not empty; choose a new folder")
        }
        guard !items.isEmpty else { throw ProjectError.invalid("No library items to export") }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries: [JSONValue] = []
        var seen: Set<String> = []
        // The same id in several scopes: the first (the one in use) wins.
        for item in items where seen.insert(item.id).inserted {
            var fields = item.fields
            fields["history"] = nil
            fields["pack"] = .string(name)
            for key in ["file", "preview"] {
                guard let path = item[key]?.string else { continue }
                guard let root = catalog.root(of: item) else {
                    throw ProjectError.invalid("library item \(item.id): \(key) has no folder")
                }
                let relative = "files/\(item.id)/\(URL(fileURLWithPath: path).lastPathComponent)"
                try LibraryStore.copy(root.appendingPathComponent(path), to: folder.appendingPathComponent(relative))
                fields[key] = .string(relative)
            }
            entries.append(.object(fields))
        }
        let manifest = JSONValue.object([
            "format": .integer(LibraryStore.format), "name": .string(name), "items": .array(entries),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        return folder
    }

    /// What `import` found in a pack before changing anything.
    public struct Contents: Sendable {
        public let name: String
        public let folder: URL
        public let items: [LibraryItem]
    }

    /// Reads and checks a pack folder: every item valid, every file inside the folder, ids unique.
    public static func read(_ folder: URL) throws -> Contents {
        let manifestURL = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ProjectError.invalid("\(folder.lastPathComponent) has no \(manifestName)")
        }
        guard case .object(let manifest) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw ProjectError.invalid("\(manifestName): expected an object")
        }
        if let format = manifest["format"]?.int, format > LibraryStore.format {
            throw ProjectError.invalid("This pack needs a newer BashCut (format \(format))")
        }
        guard let name = manifest["name"]?.string, !name.isEmpty, name.count <= 80 else {
            throw ProjectError.invalid("\(manifestName): name must be 1–80 characters")
        }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path
        var seen: Set<String> = []
        let items = try (manifest["items"]?.array ?? []).map { value -> LibraryItem in
            var item = LibraryItem(fields: value.object)
            if item.pack == nil { item["pack"] = .string(name) }
            try item.validate(root: folder)
            for path in [item.file, item.preview].compactMap({ $0 }) {
                let resolved = folder.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL.path
                guard resolved.hasPrefix(base + "/") else {
                    throw ProjectError.invalid("library item \(item.id): \(path) points outside the pack")
                }
            }
            guard seen.insert(item.id).inserted else { throw ProjectError.invalid("\(manifestName): duplicate id \(item.id)") }
            return item
        }
        guard !items.isEmpty else { throw ProjectError.invalid("\(manifestName) has no items") }
        return Contents(name: name, folder: folder, items: items)
    }

    /// Adds a pack's items to a writable scope. Ids already there are refused unless `replace`, which saves them as
    /// new versions. Items keep their `createdBy`; those without one get `createdBy`. Nothing changes on an error
    /// found before the first write.
    @discardableResult
    public static func importItems(
        _ pack: Contents, into scope: LibraryScope, catalog: LibraryCatalog, replace: Bool, createdBy: JSONValue,
        now: Date = Date()
    ) throws -> [LibraryItem] {
        let store = try catalog.store(scope)
        let existing = Set(try store.items().map(\.id))
        for item in pack.items { try catalog.checkNotBuiltIn(item.id) }
        let conflicts = pack.items.map(\.id).filter(existing.contains)
        if !replace, !conflicts.isEmpty {
            throw ProjectError.invalid(
                "The \(scope.rawValue) library already has \(conflicts.joined(separator: ", ")); pass replace to save "
                    + "them as new versions")
        }
        return try pack.items.map { item in
            var item = item
            if item["createdBy"] == nil { item["createdBy"] = createdBy }
            item["importedFrom"] = .string(pack.name)
            let file = item.file.map { pack.folder.appendingPathComponent($0) }
            let preview = item.preview.map { pack.folder.appendingPathComponent($0) }
            if existing.contains(item.id) {
                var changes = item.fields
                for key in LibraryStore.managedKeys { changes[key] = nil }
                return try store.update(item.id, changes: changes, file: file, preview: preview, now: now)
            }
            item["file"] = nil
            item["preview"] = nil
            return try store.add(item, file: file, preview: preview, now: now)
        }
    }

    /// The pack folder at `url`: the folder itself, or a .zip unpacked into `scratch` (its root or one top folder).
    public static func folder(at url: URL, scratch: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ProjectError.invalid("No pack at \(url.path)")
        }
        if isDirectory.boolValue { return url }
        guard url.pathExtension.lowercased() == "zip" else {
            throw ProjectError.invalid("A pack is a folder with \(manifestName) or a .zip of one")
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, scratch.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProjectError.invalid("Could not unpack \(url.lastPathComponent)") }
        if FileManager.default.fileExists(atPath: scratch.appendingPathComponent(manifestName).path) { return scratch }
        let entries = try FileManager.default.contentsOfDirectory(
            at: scratch, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ).filter { $0.lastPathComponent != "__MACOSX" }
        guard entries.count == 1, FileManager.default.fileExists(atPath: entries[0].appendingPathComponent(manifestName).path)
        else { throw ProjectError.invalid("\(url.lastPathComponent) has no \(manifestName)") }
        return entries[0]
    }
}
