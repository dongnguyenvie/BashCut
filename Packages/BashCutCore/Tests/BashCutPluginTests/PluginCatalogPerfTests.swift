import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Times a catalog refresh with many installed plugins (#103). Runs only with BASHCUT_PERF=1
/// (`scripts/verify.sh perf`): generating the plugins takes a while.
@Suite("Plugin catalog performance", .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"))
struct PluginCatalogPerfTests {
    /// N trusted plugins, each with `files` extra files in a node_modules-like tree.
    private static func generate(count: Int, files: Int) throws -> (root: URL, store: PluginTrustStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-perf-" + UUID().uuidString)
        let plugins = root.appendingPathComponent("plugins")
        let store = PluginTrustStore(url: root.appendingPathComponent("trust.json"))
        let encoder = JSONEncoder()
        for index in 0..<count {
            let id = String(format: "perf.plugin%04d", index)
            let directory = plugins.appendingPathComponent(id)
            let modules = directory.appendingPathComponent("node_modules/dep/lib")
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
            let manifest = PluginManifest(
                id: id, name: LocalizedText(["en": "Perf \(index)"]), version: "1.0.0", entrypoint: "bin/provider",
                capabilities: ["audio.beats"])
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
            let entrypoint = directory.appendingPathComponent("bin/provider")
            try Data("#!/bin/sh\necho \(index)\n".utf8).write(to: entrypoint)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
            for file in 0..<files {
                try Data("module.exports = \(file)\n".utf8).write(to: modules.appendingPathComponent("f\(file).js"))
            }
            try store.trust(InstalledPlugin(manifest: manifest, directory: directory))
        }
        return (root, store)
    }

    private static func time(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    @Test("Refresh with many plugins", arguments: [(1000, 5), (100, 2000)])
    func refresh(_ scenario: (count: Int, files: Int)) throws {
        let (root, trusted) = try Self.generate(count: scenario.count, files: scenario.files)
        defer { try? FileManager.default.removeItem(at: root) }
        let roots = [root.appendingPathComponent("plugins")]
        // A new store, as after a relaunch: nothing is cached yet.
        let store = PluginTrustStore(url: trusted.url)
        let cache = PluginCatalogCache()
        var plugins: [InstalledPlugin] = []
        let discover = Self.time { plugins = PluginCatalog.discover(in: roots, cache: cache).plugins }
        #expect(plugins.count == scenario.count)
        var ready = 0
        let cold = Self.time { ready = plugins.filter { store.availability(of: $0) == .ready }.count }
        #expect(ready == scenario.count)
        let warm = Self.time { ready = plugins.filter { store.availability(of: $0) == .ready }.count }
        #expect(ready == scenario.count)
        // What a refresh does on the main actor now: cached discovery and the last known availability.
        let refresh = Self.time {
            plugins = PluginCatalog.discover(in: roots, cache: cache).plugins
            ready = plugins.filter { store.knownAvailability(of: $0) == .ready }.count
        }
        #expect(ready == scenario.count)
        print(String(
            format: "[perf] %d plugins × %d files: first discover %.1f ms, file check cold %.1f ms, warm %.1f ms; "
                + "refresh %.1f ms",
            scenario.count, scenario.files, discover, cold, warm, refresh))
        #expect(refresh < 50, "refresh with \(scenario.count) plugins took \(refresh) ms")
    }
}
