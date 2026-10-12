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
        // Cancel once the helper runs: waits for the event (up to 20 s on a loaded machine), not a fixed delay.
        for _ in 0..<1_000 where !Self.hasPID(pidFile) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(Self.hasPID(pidFile), "the plugin started its helper")
        call.cancel()
        await #expect(throws: PluginError.invalid("Plugin request was cancelled")) { try await call.value }
        #expect(Date().timeIntervalSince(started) < 15, "well before the 30 s sleep, with room for a loaded machine")
        let helper = try #require(pid_t(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        // The group is killed before the call returns; the helper may take a moment to be reaped.
        for _ in 0..<250 where kill(helper, 0) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(helper, 0) != 0)
    }

    /// The helper wrote its whole PID line.
    private static func hasPID(_ file: URL) -> Bool {
        (try? String(contentsOf: file, encoding: .utf8))?.hasSuffix("\n") == true
    }

    @Test("Timeouts terminate the plugin and report a timeout")
    func timeout() async throws {
        let (plugin, root) = try makePlugin(body: "sleep 30")
        defer { try? FileManager.default.removeItem(at: root) }
        let started = Date()
        await #expect(throws: PluginError.invalid("Plugin request timed out")) {
            try await PluginProcessRunner(timeout: 0.3).call(plugin: plugin, method: "fixture.run")
        }
        #expect(Date().timeIntervalSince(started) < 15, "well before the 30 s sleep, with room for a loaded machine")
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
