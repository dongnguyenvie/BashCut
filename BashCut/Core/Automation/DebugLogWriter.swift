import Darwin
import Foundation

/// Persistent append-only handles. A separate, never-rotated lock file serializes writers across processes.
final class DebugLogWriter: @unchecked Sendable {
    private let url: URL
    private let maximumBytes: UInt64
    private let mutex = NSLock()
    private var descriptor: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var identity: (device: dev_t, inode: ino_t)?
    private var openings = 0
    var openCount: Int { mutex.withLock { openings } }

    init(url: URL, maximumBytes: UInt64) {
        self.url = url
        self.maximumBytes = maximumBytes
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
        if lockDescriptor >= 0 { close(lockDescriptor) }
    }

    func append(_ line: String) {
        mutex.lock()
        defer { mutex.unlock() }
        guard prepareLock() else { return }
        while flock(lockDescriptor, LOCK_EX) != 0 { if errno != EINTR { return } }
        defer { flock(lockDescriptor, LOCK_UN) }
        var info = stat()
        let exists = lstat(url.path, &info) == 0
        if exists, info.st_mode & mode_t(S_IFMT) != mode_t(S_IFREG) { return }
        // Another process may have rotated the file while this writer was idle.
        if descriptor < 0 || !exists || identity?.device != info.st_dev || identity?.inode != info.st_ino {
            guard openLog() else { return }
        }
        if exists, info.st_mode & 0o777 != 0o600, fchmod(descriptor, 0o600) != 0 { return }
        if exists, info.st_size > maximumBytes {
            // debug.log → debug.1.log; a custom BASHCUT_DEBUG_LOG_PATH keeps its own name beside it.
            let name = url.deletingPathExtension().lastPathComponent + ".1" + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
            let rotated = url.deletingLastPathComponent().appendingPathComponent(name)
            guard rename(url.path, rotated.path) == 0, openLog() else { return }
        }
        writeLine(line)
    }

    private func writeLine(_ line: String) {
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

    private func prepareLock() -> Bool {
        if lockDescriptor >= 0 { return true }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch { return false }
        lockDescriptor = secureOpen(url.appendingPathExtension("lock"), flags: O_RDWR)
        return lockDescriptor >= 0
    }

    private func openLog() -> Bool {
        if descriptor >= 0 { close(descriptor) }
        descriptor = secureOpen(url, flags: O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { identity = nil; return false }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { close(descriptor); descriptor = -1; return false }
        identity = (info.st_dev, info.st_ino)
        openings += 1
        return true
    }

    private func secureOpen(_ url: URL, flags: Int32) -> Int32 {
        let file = open(url.path, flags | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard file >= 0 else { return -1 }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), fchmod(file, 0o600) == 0 else {
            close(file)
            return -1
        }
        return file
    }
}
