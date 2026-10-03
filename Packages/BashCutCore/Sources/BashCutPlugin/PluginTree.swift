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

    static func stamp(_ folder: URL) throws -> [String] {
        try entries(folder).map { entry in
            let info = entry.info
            return "\(entry.relative)|\(info.st_dev)|\(info.st_ino)|\(info.st_mode)|\(info.st_size)|"
                + "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)|"
                + "\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)|\(entry.link ?? "")"
        }
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
