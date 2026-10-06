import BashCutDocument
import BashCutEngine
import BashCutPlugin
import Foundation
import Testing

@Suite("Storage usage")
struct StorageUsageTests {
    @Test("Measures plugin data, caches and proxies; clears only what can be made again")
    func measureAndClear() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data"), cacheRoot = root.appendingPathComponent("cache")
        for folder in [data, cacheRoot] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("acme.voice"), withIntermediateDirectories: true)
        }
        try Data(count: 10_000).write(to: cacheRoot.appendingPathComponent("acme.voice/model.bin"))
        try Data(count: 2_000).write(to: data.appendingPathComponent("acme.voice/env.txt"))
        let project = root.appendingPathComponent("project")
        let proxies = StorageUsage.proxiesFolder(projectRoot: project)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try Data(count: 5_000).write(to: proxies.appendingPathComponent("m1.mov"))
        let rampAudio = ProjectCache.url(.rampAudio, projectRoot: project)
        try FileManager.default.createDirectory(at: rampAudio, withIntermediateDirectories: true)
        try Data(count: 12_000).write(to: rampAudio.appendingPathComponent("ramp.caf"))
        let plugins = root.appendingPathComponent("Plugins")

        func measure() -> [StorageEntry] {
            StorageUsage.measure(projectRoot: project, pluginsFolder: plugins,
                                 pluginDataRoot: data, pluginCacheRoot: cacheRoot, supportRoot: root,
                                 registryRoot: root.appendingPathComponent("registry"))
        }
        let entries = measure()
        #expect(entries.allSatisfy { $0.url.path.hasPrefix(root.path + "/") })
        let cache = try #require(entries.first { $0.kind == .pluginCache && $0.pluginID == "acme.voice" })
        #expect(cache.bytes >= 10_000)
        #expect(entries.contains { $0.kind == .pluginData && $0.pluginID == "acme.voice" && $0.bytes >= 2_000 })
        let proxyEntry = try #require(entries.first { $0.kind == .proxies })
        #expect(proxyEntry.bytes >= 5_000 && proxyEntry.clearable)
        let rampEntry = try #require(entries.first { $0.kind == .rampAudio })
        #expect(rampEntry.bytes >= 12_000 && rampEntry.clearable)
        let audit = try #require(entries.first { $0.kind == .audit })
        #expect(!audit.clearable)
        #expect(throws: StorageUsageError.self) { try StorageUsage.clear(audit) }

        try StorageUsage.clear(cache)
        try StorageUsage.clear(proxyEntry)
        try StorageUsage.clear(rampEntry)
        let after = measure()
        #expect(!after.contains { $0.kind == .pluginCache })
        #expect(after.first { $0.kind == .proxies }?.bytes == 0)
        #expect(after.first { $0.kind == .rampAudio }?.bytes == 0)
        #expect(after.contains { $0.kind == .pluginData })
    }

    @Test("Groups each plugin's code, data and cache into one total, largest first; shared runtimes stand apart")
    func pluginTotals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let plugins = root.appendingPathComponent("Plugins"), data = root.appendingPathComponent("data")
        let cacheRoot = root.appendingPathComponent("cache")
        func write(_ folder: URL, _ id: String, _ bytes: Int) throws {
            let url = folder.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url.appendingPathComponent("file.bin"))
        }
        // small: 1 KB code only. big: 4 KB code + 20 KB data + 30 KB cache. mid: 40 KB cache left after removal.
        try write(plugins, "acme.small", 1_000)
        try write(plugins, "acme.big", 4_000)
        try write(data, "acme.big", 20_000)
        try write(cacheRoot, "acme.big", 30_000)
        try write(cacheRoot, "acme.mid", 40_000)
        try write(plugins, ".previous", 90_000)
        try write(data, PluginFolders.sharedName, 50_000)
        try write(cacheRoot, PluginFolders.sharedName, 60_000)
        let entries = StorageUsage.measure(projectRoot: nil, pluginsFolder: plugins,
                                           pluginDataRoot: data, pluginCacheRoot: cacheRoot, supportRoot: root,
                                           registryRoot: root.appendingPathComponent("registry"))
        #expect(!entries.contains { $0.url.lastPathComponent == ".previous" })
        let grouped = StorageUsage.byPlugin(entries)
        #expect(grouped.map(\.pluginID) == ["acme.big", "acme.mid", "acme.small"])
        let big = try #require(grouped.first)
        #expect(big.entries.map(\.kind) == [.plugins, .pluginData, .pluginCache])
        #expect(big.bytes == big.entries.reduce(0) { $0 + $1.bytes } && big.bytes >= 54_000)
        #expect(big.installed && !grouped[1].installed && grouped[2].installed)
        #expect(!(big.entries.first?.clearable ?? true))
        // The shared folders are their own clearable rows, never a plugin.
        #expect(!grouped.contains { $0.pluginID == PluginFolders.sharedName })
        let shared = entries.filter { $0.kind == .sharedData || $0.kind == .sharedCache }
        #expect(shared.map(\.kind) == [.sharedData, .sharedCache])
        #expect(shared.allSatisfy { $0.pluginID == nil && $0.clearable && $0.bytes >= 50_000 })
    }

    @Test("Sizes count nested and hidden files, skip links and are 0 for a missing path")
    func sizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 8_192).write(to: nested.appendingPathComponent("one.bin"))
        try Data(count: 8_192).write(to: root.appendingPathComponent(".hidden"))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(count: 1_000_000).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)

        let total = StorageUsage.size(of: root)
        #expect(total >= 16_384 && total < 1_000_000)
        #expect(StorageUsage.size(of: nested.appendingPathComponent("one.bin")) >= 8_192)
        #expect(StorageUsage.size(of: root.appendingPathComponent("missing")) == 0)
    }
}
