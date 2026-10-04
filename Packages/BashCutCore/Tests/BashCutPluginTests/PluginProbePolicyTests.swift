import Foundation
import Testing

@testable import BashCutPlugin

@Suite("Dependency probe policy")
struct PluginProbePolicyTests {
    @Test("Inline interpreter code is refused, including combined and long flags", arguments: [
        ("sh", ["check"]), ("/bin/bash", ["-c", "true"]), ("env", ["python3"]), ("python3", ["-c", "1"]),
        ("python3", ["-cimport os"]), ("python3.12", ["-Bc", "1"]), ("node", ["--eval", "1"]), ("node", ["--eval=1"]),
        ("node", ["-p", "1"]), ("perl", ["-E", "say 1"]), ("ruby", ["-e", "1"]), ("php", ["-r", "1;"]),
        ("deno", ["eval", "1"])
    ])
    func refused(_ executable: String, _ arguments: [String]) {
        #expect(PluginProcessRunner.runsInlineCode(PluginCommand(executable: executable, arguments: arguments)))
    }

    @Test("Tools and interpreter files remain allowed", arguments: [
        ("grep", ["-e", "pattern", "file"]), ("ffmpeg", ["-version"]), ("python3", ["bin/check.py"]),
        ("python3", ["-m", "whisper", "--help"]), ("node", ["--version"]), ("bin/check", ["-c"])
    ])
    func allowed(_ executable: String, _ arguments: [String]) {
        #expect(!PluginProcessRunner.runsInlineCode(PluginCommand(executable: executable, arguments: arguments)))
    }

    @Test("Plugin processes never write Python bytecode beside pinned files")
    func bytecode() {
        let plugin = InstalledPlugin(
            manifest: PluginManifest(id: "test.env", name: "Env", version: "0.0.1", entrypoint: "run", capabilities: ["audio.beats"]),
            directory: FileManager.default.temporaryDirectory)
        #expect(PluginProcessRunner.environment(for: plugin, inheriting: [:])["PYTHONDONTWRITEBYTECODE"] == "1")
    }
}
