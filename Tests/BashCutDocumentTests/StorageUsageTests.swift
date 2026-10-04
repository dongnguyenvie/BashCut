import BashCutDocument
import BashCutPlugin
import Foundation
import Testing

@Suite("Storage usage", .serialized)
struct StorageUsageTests {
    @Test("Measures plugin data, caches and proxies; clears only what can be made again")
    func measureAndClear() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("BASHCUT_PLUGIN_STATE_ROOT", root.appendingPathComponent("state").path, 1)
        defer { unsetenv("BASHCUT_PLUGIN_STATE_ROOT") }
        PluginFolders.prepare("acme.voice")
        try Data(count: 10_000).write(to: PluginFolders.cache("acme.voice").appendingPathComponent("model.bin"))
        try Data(count: 2_000).write(to: PluginFolders.data("acme.voice").appendingPathComponent("env.txt"))
        let project = root.appendingPathComponent("project")
        let proxies = StorageUsage.proxiesFolder(projectRoot: project)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try Data(count: 5_000).write(to: proxies.appendingPathComponent("m1.mov"))
        let rampAudio = project.appendingPathComponent(".bashcut/ramped-audio")
        try FileManager.default.createDirectory(at: rampAudio, withIntermediateDirectories: true)
        try Data(count: 12_000).write(to: rampAudio.appendingPathComponent("ramp.caf"))
        let plugins = root.appendingPathComponent("Plugins")

        let entries = StorageUsage.measure(projectRoot: project, pluginsFolder: plugins)
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
        let after = StorageUsage.measure(projectRoot: project, pluginsFolder: plugins)
        #expect(!after.contains { $0.kind == .pluginCache })
        #expect(after.first { $0.kind == .proxies }?.bytes == 0)
        #expect(after.first { $0.kind == .rampAudio }?.bytes == 0)
        #expect(after.contains { $0.kind == .pluginData })
    }
}
