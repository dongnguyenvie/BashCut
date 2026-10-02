import BashCutPlugin
import Darwin
import Foundation
import Testing

@Suite("Plugin process lifecycle")
struct PluginProcessLifecycleTests {
    @Test("Cancelling a call stops promptly and kills helpers the plugin started")
    func cancellationKillsProcessGroup() async throws {
        let (plugin, root) = try makePlugin(
            body: """
                sleep 30 &
                echo $! > "$BASHCUT_PLUGIN_DIR/../helper.pid"
                sleep 30
                """)
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Date()
        let call = Task { try await PluginProcessRunner(timeout: 60).call(plugin: plugin, method: "fixture.run") }
        let pidFile = root.appendingPathComponent("helper.pid")
        for _ in 0..<250 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        call.cancel()
        await #expect(throws: PluginError.invalid("Plugin request was cancelled")) { try await call.value }
        #expect(Date().timeIntervalSince(started) < 5)
        let helper = try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(kill(helper, 0) != 0)
    }

    @Test("Timeouts terminate the plugin and report a timeout")
    func timeout() async throws {
        let (plugin, root) = try makePlugin(body: "sleep 30")
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Date()
        await #expect(throws: PluginError.invalid("Plugin request timed out")) {
            try await PluginProcessRunner(timeout: 0.3).call(plugin: plugin, method: "fixture.run")
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("Nonzero exits surface stderr")
    func failureDetail() async throws {
        let (plugin, root) = try makePlugin(body: "echo 'model missing' >&2\nexit 3")
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: PluginError.invalid("Plugin failed: model missing")) {
            try await PluginProcessRunner(timeout: 5).call(plugin: plugin, method: "fixture.run")
        }
    }

    private func makePlugin(body: String) throws -> (InstalledPlugin, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider.sh")
        try Data("#!/bin/sh\ncat > /dev/null\n\(body)\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "app.bashcut.lifecycle", name: "Lifecycle", version: "1.0.0",
            entrypoint: "provider.sh", capabilities: ["audio.beats"])
        return (InstalledPlugin(manifest: manifest, directory: directory), root)
    }
}
