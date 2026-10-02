import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@Suite("Plugin trust gate")
struct PluginTrustTests {
    private struct Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        func plugin(in folder: String = "user", id: String = "example.trust") throws -> InstalledPlugin {
            let directory = root.appendingPathComponent(folder).appendingPathComponent(id)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
            let manifest = PluginManifest(
                id: id, name: "Trust", version: "1.0.0", entrypoint: "bin/provider", capabilities: ["audio.beats"])
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
            let entrypoint = directory.appendingPathComponent("bin/provider")
            try Data("#!/bin/sh\necho v1\n".utf8).write(to: entrypoint)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
            return InstalledPlugin(manifest: manifest, directory: directory)
        }

        func store() -> PluginTrustStore {
            PluginTrustStore(
                url: root.appendingPathComponent("trust.json"), trustedRoots: [root.appendingPathComponent("bundled")])
        }
    }

    @Test("Plugins run only after approval and again need it when their files change")
    func approval() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let plugin = try sandbox.plugin()
        let store = sandbox.store()
        #expect(store.availability(of: plugin) == .untrusted)
        try store.trust(plugin)
        #expect(store.availability(of: plugin) == .ready)
        // A new store reads the pin from disk.
        #expect(sandbox.store().availability(of: plugin) == .ready)
        try Data("#!/bin/sh\necho v2\n".utf8).write(to: plugin.directory.appendingPathComponent("bin/provider"))
        #expect(store.availability(of: plugin) == .changed)
        try store.trust(plugin)
        #expect(store.availability(of: plugin) == .ready)
        try store.revoke(plugin.id)
        #expect(store.availability(of: plugin) == .untrusted)
    }

    @Test("Bundled plugins are trusted; any plugin can be turned off")
    func bundledAndDisabled() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let bundled = try sandbox.plugin(in: "bundled", id: "example.bundled")
        let store = sandbox.store()
        #expect(store.availability(of: bundled) == .ready)
        try store.setEnabled(bundled, enabled: false)
        #expect(store.availability(of: bundled) == .disabled)
        try store.setEnabled(bundled, enabled: true, hooks: false)
        #expect(store.availability(of: bundled) == .ready)
        #expect(!store.hooksEnabled(bundled.id))
        // Turning on an unapproved plugin does not trust it.
        let user = try sandbox.plugin()
        try store.setEnabled(user, enabled: true)
        #expect(store.availability(of: user) == .untrusted)
    }

    @Test("User option values persist")
    func userOptions() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        try sandbox.store().setUserOption("example.trust", key: "voice", value: .string("female"))
        #expect(sandbox.store().userOptions("example.trust") == ["voice": .string("female")])
        try sandbox.store().setUserOption("example.trust", key: "voice", value: nil)
        #expect(sandbox.store().userOptions("example.trust").isEmpty)
    }
}
