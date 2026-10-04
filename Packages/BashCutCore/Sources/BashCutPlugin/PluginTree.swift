import CryptoKit
import Darwin
import Foundation

/// Walk with relative names and fresh lstat metadata: URL resource caches and /var aliases cannot hide edits.
enum PluginTree {
    private struct Entry {
        let path: String
        let relative: String
        let info: stat
        let link: String?
    }

    static func digest(_ folder: URL) throws -> String {
        let lines = try entries(folder).map { entry -> String in
            if let link = entry.link { return "\(entry.relative)\0link\0\(link)" }
            if entry.info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
                let data = try Data(contentsOf: URL(fileURLWithPath: entry.path))
                return "\(entry.relative)\0\(entry.info.st_mode)\0\(PluginFingerprint.hex(data))"
            }
            return "\(entry.relative)\0directory\0\(entry.info.st_mode)"
        }
        return PluginFingerprint.hex(Data(lines.joined(separator: "\n").utf8))
    }

    /// A change detector over fresh lstat metadata, run on every trust check. It walks with fts(3) and hashes
    /// raw fields instead of building a string per entry: a dev-linked plugin with node_modules (~13k entries)
    /// took ~190 ms per check, now ~45 ms. Link validation stays in `digest`, which runs whenever this changes.
    static func stamp(_ folder: URL) throws -> String {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard let rootPath = strdup(root) else { throw PluginError.invalid("Cannot inspect the plugin folder") }
        defer { free(rootPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        // Siblings share their parent's path, so comparing full paths orders them by name.
        guard let walk = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR, { first, second in
            guard let first = first?.pointee, let second = second?.pointee else { return 0 }
            return strcmp(first.pointee.fts_path, second.pointee.fts_path)
        }) else { throw PluginError.invalid("Cannot inspect the plugin folder") }
        defer { fts_close(walk) }
        var hasher = SHA256()
        errno = 0
        while let entry = fts_read(walk) {
            let item = entry.pointee
            if Int32(item.fts_info) == FTS_DP { continue }
            guard ![FTS_ERR, FTS_DNR, FTS_NS].contains(Int32(item.fts_info)) else {
                throw PluginError.invalid("Cannot inspect plugin file: \(String(cString: item.fts_path))")
            }
            if isFinderMetadata(item) {
                if Int32(item.fts_info) == FTS_D { fts_set(walk, entry, FTS_SKIP) }
                continue
            }
            try update(&hasher, with: item)
        }
        // fts_read returns nil with errno 0 once the whole hierarchy is visited; anything else is a failed read.
        guard errno == 0 else { throw PluginError.invalid("Cannot finish inspecting the plugin folder") }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func isFinderMetadata(_ item: FTSENT) -> Bool {
        let path = UnsafeRawBufferPointer(start: item.fts_path, count: Int(item.fts_pathlen))
        return item.fts_namelen == 9 && path.suffix(9).elementsEqual(".DS_Store".utf8)
    }

    /// Path, identity, mode, size, both timestamps and, for links, the target text.
    private static func update(_ hasher: inout SHA256, with item: FTSENT) throws {
        guard var info = item.fts_statp?.pointee else { throw PluginError.invalid("Cannot inspect the plugin folder") }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: item.fts_path, count: Int(item.fts_pathlen)))
        for field in [UInt64(info.st_dev), info.st_ino, UInt64(info.st_mode), UInt64(bitPattern: info.st_size)] {
            withUnsafeBytes(of: field) { hasher.update(bufferPointer: $0) }
        }
        withUnsafeBytes(of: &info.st_mtimespec) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: &info.st_ctimespec) { hasher.update(bufferPointer: $0) }
        guard Int32(item.fts_info) == FTS_SL || Int32(item.fts_info) == FTS_SLNONE else { return }
        var target = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = readlink(item.fts_path, &target, target.count)
        guard count >= 0 else { throw PluginError.invalid("Cannot read plugin link: \(String(cString: item.fts_path))") }
        target.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
    }

    private static func entries(_ folder: URL) throws -> [Entry] {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let manager = FileManager.default
        var result: [Entry] = []
        func visit(_ relative: String) throws {
            let path = relative.isEmpty ? root : root + "/" + relative
            var info = stat()
            guard lstat(path, &info) == 0 else { throw PluginError.invalid("Cannot inspect plugin file: \(relative)") }
            let kind = info.st_mode & mode_t(S_IFMT)
            var link: String?
            if kind == mode_t(S_IFLNK) {
                let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                guard target.hasPrefix(root + "/"), manager.fileExists(atPath: target) else {
                    throw PluginError.invalid("Plugin symlink leaves its folder or has no target: \(relative)")
                }
                link = try manager.destinationOfSymbolicLink(atPath: path)
            } else if kind != mode_t(S_IFREG), kind != mode_t(S_IFDIR) {
                throw PluginError.invalid("Unsupported file in plugin: \(relative)")
            }
            result.append(Entry(path: path, relative: relative, info: info, link: link))
            if kind == mode_t(S_IFDIR) {
                for name in try manager.contentsOfDirectory(atPath: path).sorted() where name != ".DS_Store" {
                    try visit(relative.isEmpty ? name : relative + "/" + name)
                }
            }
        }
        try visit("")
        return result
    }
}
