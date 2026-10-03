import Darwin
import Foundation

/// Private append-only writes; never follow a replacement symlink when opening a log file.
enum DebugLogFile {
    static func append(_ line: String, to url: URL, maximumBytes: UInt64) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        var descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              fchmod(descriptor, 0o600) == 0 else { return }
        if info.st_size > maximumBytes {
            let rotated = url.deletingLastPathComponent().appendingPathComponent("debug.1.log")
            try? manager.removeItem(at: rotated)
            do { try manager.moveItem(at: url, to: rotated) } catch { return }
            close(descriptor)
            descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
            guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else { return }
        }
        Data(line.utf8).withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(descriptor, address.advanced(by: written), buffer.count - written)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                written += count
            }
        }
    }
}
