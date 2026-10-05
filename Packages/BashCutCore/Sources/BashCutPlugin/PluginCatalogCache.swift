import Darwin
import Foundation

/// A file's identity, mode, size and both timestamps from stat(2). Writing, replacing, renaming over or changing
/// the mode of the file changes it.
struct PluginFileSignature: Sendable, Equatable {
    let device: UInt64
    let inode: UInt64
    let mode: UInt64
    let size: Int64
    let modified: [Int]
    let changed: [Int]

    /// Nil when the file is missing. Follows links, as reading the file does.
    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = UInt64(info.st_dev)
        inode = info.st_ino
        mode = UInt64(info.st_mode)
        size = info.st_size
        modified = [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec]
        changed = [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec]
    }

    /// plugin.json and the entrypoint: what discovery reads and what the trust pin hashes besides the tree.
    static func manifestAndEntrypoint(of plugin: InstalledPlugin) -> [PluginFileSignature?] {
        manifestAndEntrypoint(directoryPath: plugin.directoryPath, entrypoint: plugin.manifest.entrypoint)
    }

    static func manifestAndEntrypoint(directoryPath: String, entrypoint: String) -> [PluginFileSignature?] {
        [PluginFileSignature(path: directoryPath + "/plugin.json"),
         PluginFileSignature(path: directoryPath + "/" + entrypoint)]
    }
}

/// Plugins already read by `PluginCatalog.discover`, reused while their plugin.json and entrypoint keep the same
/// signature, so a refresh with many plugins does not decode and validate every manifest again (#103).
public final class PluginCatalogCache: @unchecked Sendable {
    private struct Entry {
        let signatures: [PluginFileSignature?]
        let plugin: InstalledPlugin
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    /// The plugin in the folder at `path` (standardized) as last read, or nil when it was never read or its files
    /// changed since.
    func plugin(at path: String) -> InstalledPlugin? {
        guard let entry = locked({ entries[path] }) else { return nil }
        let current = PluginFileSignature.manifestAndEntrypoint(
            directoryPath: path, entrypoint: entry.plugin.manifest.entrypoint)
        guard current.allSatisfy({ $0 != nil }), current == entry.signatures else {
            locked { entries[path] = nil }
            return nil
        }
        return entry.plugin
    }

    /// Records a plugin that read and validated; `signatures` were taken before reading it, so a write while it
    /// was read is seen on the next refresh.
    func store(_ plugin: InstalledPlugin, signatures: [PluginFileSignature?]) {
        guard signatures.allSatisfy({ $0 != nil }) else { return }
        locked { entries[plugin.directoryPath] = Entry(signatures: signatures, plugin: plugin) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
