import BashCutProject
import Foundation

/// Builder-owned, bounded cache. Each build resolves a LUT once; subsequent builds reuse the parsed cube while
/// its file signature is unchanged. URLs, not project-local IDs, prevent cross-project reuse.
struct LUTCache {
    private struct Signature: Equatable {
        let modified: Date?
        let inode: UInt64?
        let size: Int?

        init(_ url: URL) throws {
            // URL.resourceValues can retain cached metadata after an atomic replacement or deletion.
            let values = try FileManager.default.attributesOfItem(atPath: url.path)
            modified = values[.modificationDate] as? Date
            inode = (values[.systemFileNumber] as? NSNumber)?.uint64Value
            size = values[.size] as? Int
        }
    }

    private struct Entry {
        let signature: Signature
        let value: CubeLUT
    }

    private var entries: [URL: Entry] = [:]
    private var order: [URL] = []
    private(set) var loads = 0
    private(set) var bytes = 0
    let maximumBytes: Int

    init(maximumBytes: Int = 64 * 1024 * 1024) { self.maximumBytes = max(0, maximumBytes) }

    mutating func load(_ url: URL, dimension: Int) throws -> CubeLUT {
        let signature = try Signature(url)
        if let entry = entries[url], entry.signature == signature {
            guard entry.value.dimension == dimension else { throw ProjectError.invalid("LUT size changed on disk") }
            order.removeAll { $0 == url }
            order.append(url)
            return entry.value
        }
        remove(url)
        let value = try CubeLUT.load(url)
        guard value.dimension == dimension else { throw ProjectError.invalid("LUT size changed on disk") }
        loads += 1
        guard value.cubeData.count <= maximumBytes else { return value }
        while bytes + value.cubeData.count > maximumBytes, let oldest = order.first { remove(oldest) }
        entries[url] = Entry(signature: signature, value: value)
        bytes += value.cubeData.count
        order.append(url)
        return value
    }

    private mutating func remove(_ url: URL) {
        if let removed = entries.removeValue(forKey: url) { bytes -= removed.value.cubeData.count }
        order.removeAll { $0 == url }
    }
}
