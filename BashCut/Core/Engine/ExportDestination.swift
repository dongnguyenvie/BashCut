import BashCutProject
import Darwin
import Foundation

/// Render beside the destination so publication is one same-filesystem, exclusive rename.
/// A crash may leave a hidden staging directory, but never a partial movie at the user's final path.
struct ExportDestination {
    let final: URL
    let partial: URL
    private let directory: URL

    init(_ url: URL) throws {
        final = url
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Export destination already exists")
        }
        directory = url.deletingLastPathComponent().appendingPathComponent(
            ".bashcut-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        partial = directory.appendingPathComponent("movie.partial")
    }

    func publish() throws {
        let result = partial.withUnsafeFileSystemRepresentation { source in
            final.withUnsafeFileSystemRepresentation { destination in
                renamex_np(source, destination, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw ProjectError.invalid("Export destination already exists") }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: final.path])
        }
    }

    func discard() { try? FileManager.default.removeItem(at: directory) }
}
