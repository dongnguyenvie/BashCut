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
        // Any file in the folder counts, not only the manifest and entrypoint.
        try Data("print('a')".utf8).write(to: plugin.directory.appendingPathComponent("bin/helper.py"))
        #expect(store.availability(of: plugin) == .changed)
        try store.trust(plugin)
        #expect(store.availability(of: plugin) == .ready)
        try store.revoke(plugin)
        #expect(store.availability(of: plugin) == .untrusted)
    }

    @Test("Repair cannot silently reapprove changed files, including disabled plugins")
    func repairTrust() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let plugin = try sandbox.plugin()
        let store = sandbox.store()
        try store.validateSetup(of: plugin) // Initial setup still asks for installation approval.
        try store.trust(plugin)
        try store.validateSetup(of: plugin)
        let approved = store.grant(for: plugin)
        try Data("#!/bin/sh\necho tampered\n".utf8).write(to: plugin.directory.appendingPathComponent("bin/provider"))
        #expect(throws: PluginError.self) { try store.validateSetup(of: plugin) }
        #expect(store.grant(for: plugin) == approved)
        try store.setEnabled(plugin, enabled: false)
        #expect(store.availability(of: plugin) == .disabled)
        #expect(throws: PluginError.self) { try store.validateSetup(of: plugin) }
        try store.trust(plugin) // A separate, explicit Trust action allows repairs again.
        try store.validateSetup(of: plugin)
    }

    @Test("Older grants without a folder digest are upgraded once; dev links relax in debug builds")
    func legacyAndLinked() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let plugin = try sandbox.plugin()
        let full = try PluginFingerprint(plugin: plugin)
        let legacy = PluginFingerprint(manifestSHA256: full.manifestSHA256, entrypointSHA256: full.entrypointSHA256)
        let url = sandbox.root.appendingPathComponent("trust.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct Contents: Encodable { let grants: [String: PluginGrant]; let options: [String: [String: JSONValue]] }
        try encoder.encode(Contents(grants: [plugin.installationID: PluginGrant(fingerprint: legacy, version: "1.0.0")], options: [:]))
            .write(to: url)
        let store = sandbox.store()
        #expect(store.availability(of: plugin) == .ready)
        #expect(store.grant(for: plugin)?.fingerprint.treeSHA256 == full.treeSHA256)

        let link = sandbox.root.appendingPathComponent("user/example.linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plugin.directory)
        let linked = InstalledPlugin(manifest: plugin.manifest, directory: link)
        try store.trust(linked)
        try Data("print('b')".utf8).write(to: plugin.directory.appendingPathComponent("bin/helper.py"))
        #expect(store.availability(of: linked) == .changed)
        store.relaxesLinkedPlugins = true
        #expect(store.availability(of: linked) == .ready)
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
        #expect(!store.hooksEnabled(bundled))
        // Turning on an unapproved plugin does not trust it.
        let user = try sandbox.plugin()
        try store.setEnabled(user, enabled: true)
        #expect(store.availability(of: user) == .untrusted)
    }

    @Test("A project copy cannot inherit another installation's trust, options, or enabled state")
    func installations() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let user = try sandbox.plugin()
        let project = try sandbox.plugin(in: "project")
        let store = sandbox.store()
        try store.trust(user)
        try store.setUserOption(user, key: "provider", value: .string("openai"))
        #expect(store.availability(of: project) == .untrusted)
        #expect(store.userOptions(project).isEmpty)
        try store.trust(project)
        try store.setEnabled(project, enabled: false, hooks: false)
        #expect(store.availability(of: user) == .ready)
        #expect(store.hooksEnabled(user))
        try store.revoke(project)
        #expect(store.availability(of: user) == .ready)
        #expect(sandbox.store().availability(of: project) == .untrusted)
        let catalog = PluginCatalog.discover(in: [project.directory.deletingLastPathComponent(), user.directory.deletingLastPathComponent()])
        #expect(catalog.plugins.first?.installationID == project.installationID)
        #expect(catalog.diagnostics.contains { $0.contains("shadows installed plugin") })
    }

    @Test("Credential identity follows installation and code, not the decision to trust it")
    func credentialIdentity() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let user = try sandbox.plugin()
        let project = try sandbox.plugin(in: "project")
        let store = sandbox.store()
        let original = try store.credentialIdentity(for: user)
        #expect(try store.credentialIdentity(for: project) != original)
        try store.trust(project)
        #expect(try store.credentialIdentity(for: project) != original)
        #expect(try store.credentialIdentity(for: user) == original)
        try Data("changed code".utf8).write(to: user.directory.appendingPathComponent("bin/helper.py"))
        let changed = try store.credentialIdentity(for: user)
        #expect(changed != original)
        try store.trust(user)
        #expect(try store.credentialIdentity(for: user) == changed)
    }

    @Test("Legacy ID-only approvals cannot establish the root the user trusted")
    func unscopedGrant() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let plugin = try sandbox.plugin()
        let store = sandbox.store()
        try store.trust(plugin)
        var contents = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        var grants = try #require(contents["grants"] as? [String: Any])
        grants[plugin.id] = grants.removeValue(forKey: plugin.installationID)
        contents["grants"] = grants
        try JSONSerialization.data(withJSONObject: contents).write(to: store.url)
        #expect(sandbox.store().availability(of: plugin) == .untrusted)
    }

    @Test("User option values persist")
    func userOptions() throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let plugin = try sandbox.plugin()
        try sandbox.store().setUserOption(plugin, key: "voice", value: .string("female"))
        #expect(sandbox.store().userOptions(plugin) == ["voice": .string("female")])
        try sandbox.store().setUserOption(plugin, key: "voice", value: nil)
        #expect(sandbox.store().userOptions(plugin).isEmpty)
    }
}
