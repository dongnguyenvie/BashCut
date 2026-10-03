import BashCutPlugin
import Foundation
import Testing

@testable import BashCutPlugins

@Suite("Plugin health trust boundary")
struct PluginHealthTrustTests {
    @Test("Health probes reject inline interpreter commands", arguments: ["sh", "bash", "zsh", "osascript", "env"])
    func rejectsInterpreter(_ program: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: "test.inline", name: "Inline", version: "0.0.1", entrypoint: "check",
            capabilities: ["audio.beats"], dependencies: [
                PluginDependency(id: "runtime", name: "Runtime", kind: .executable,
                                 probe: PluginCommand(executable: program, arguments: ["-c", "touch probe-ran"])),
            ])
        let health = await PluginProcessRunner().health(plugin: InstalledPlugin(manifest: manifest, directory: root))
        #expect(health.state == .degraded)
        #expect(health.dependencies.first?.detail.contains("inline interpreter code") == true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("probe-ran").path))
    }

    @Test("Health checks never execute unapproved, changed, or disabled plugin code")
    func healthRequiresTrust() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("plugin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appendingPathComponent("probe-ran")
        let executable = folder.appendingPathComponent("check")
        try Data("#!/bin/sh\ntouch probe-ran\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "test.health", name: "Health", version: "0.0.1", entrypoint: "check",
            capabilities: ["audio.beats"], dependencies: [
                PluginDependency(id: "runtime", name: "Runtime", kind: .executable,
                                 probe: PluginCommand(executable: "./check")),
            ])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("plugin.json"))
        let plugin = InstalledPlugin(manifest: manifest, directory: folder)
        let trust = PluginTrustStore(url: root.appendingPathComponent("trust.json"))
        let service = CapabilityService(roots: PluginRoots(user: root, bundled: nil), trust: trust)

        let untrusted = await service.health(plugin)
        #expect(untrusted.state == .degraded)
        #expect(untrusted.dependencies.first?.state == .notChecked)
        #expect(!FileManager.default.fileExists(atPath: marker.path))

        try trust.trust(plugin)
        let approved = await service.health(plugin)
        #expect(approved.state == .ready)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try FileManager.default.removeItem(at: marker)

        try trust.setEnabled(plugin, enabled: false)
        #expect(await service.health(plugin).state == .degraded)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        try trust.setEnabled(plugin, enabled: true)
        try Data("#!/bin/sh\ntouch probe-ran\n# changed code\n".utf8).write(to: executable)
        #expect(service.availability(plugin) == .changed)
        #expect(await service.health(plugin).state == .degraded)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
