import Foundation

/// Identifies one version of a file on disk; a cached asset, ramp render or structure hash is stale once it changes.
struct FileSignature: Equatable {
    let modified: Date?
    let size: Int?
    let inode: UInt64?

    init(_ url: URL) {
        // FileManager performs a fresh stat; URL resource values can retain an older signature.
        let values = try? FileManager.default.attributesOfItem(atPath: url.path)
        modified = values?[.modificationDate] as? Date
        size = values?[.size] as? Int
        inode = values?[.systemFileNumber] as? UInt64
    }
}
