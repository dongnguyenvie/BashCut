import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin install recipes")
struct PluginRecipeRunnerTests {
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [PluginRecipeOutput] = []
        func add(_ item: PluginRecipeOutput) { lock.lock(); items.append(item); lock.unlock() }
        var all: [PluginRecipeOutput] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func plugin(_ script: String) throws -> (InstalledPlugin, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("plugin")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let setup = directory.appendingPathComponent("bin/setup")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: setup)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setup.path)
        let manifest = PluginManifest(id: "test.recipe", name: "Recipe", version: "1.0.0", entrypoint: "bin/setup",
                                      capabilities: ["audio.beats"])
        return (InstalledPlugin(manifest: manifest, directory: directory), root)
    }

    @Test("Output streams line by line, progress lines parse, and the environment is filtered")
    func output() async throws {
        let (plugin, root) = try plugin("""
            echo "::progress 0.5 Downloading model"
            echo "secret=${BASHCUT_TEST_SECRET:-unset} data=${BASHCUT_PLUGIN_DATA##*/}"
            echo oops >&2
            """)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = Lines()
        try await PluginRecipeRunner.run(
            PluginCommand(executable: "bin/setup"), plugin: plugin, directory: plugin.directory,
            inheritedEnvironment: ["PATH": "/usr/bin:/bin", "BASHCUT_TEST_SECRET": "leak"], output: lines.add)
        #expect(lines.all == [
            .progress(0.5, "Downloading model"), .line("secret=unset data=test.recipe"), .line("oops"),
        ])
    }

    @Test("A failing recipe reports its output; cancelling stops it")
    func failureAndCancel() async throws {
        let (failing, root) = try plugin("echo 'pip: no matching distribution'; exit 2")
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: PluginError.invalid("Dependency install failed: pip: no matching distribution")) {
            try await PluginRecipeRunner.run(
                PluginCommand(executable: "bin/setup"), plugin: failing, directory: failing.directory, output: { _ in })
        }
        let (slow, slowRoot) = try plugin("sleep 30")
        defer { try? FileManager.default.removeItem(at: slowRoot) }
        let started = Date()
        let task = Task {
            try await PluginRecipeRunner.run(
                PluginCommand(executable: "bin/setup"), plugin: slow, directory: slow.directory, output: { _ in })
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
