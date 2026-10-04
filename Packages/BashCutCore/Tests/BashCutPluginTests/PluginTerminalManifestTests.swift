import BashCutPlugin
import Foundation
import Testing

@Suite("Plugin API 5: agent.terminal manifests")
struct PluginTerminalManifestTests {
    private func manifest(_ terminal: String?, apiVersion: Int = 5, capabilities: String = #"["agent.terminal"]"#)
        throws -> PluginManifest
    {
        let json = """
            {"schema": "bashcut.plugin/1", "id": "dev.example.gemini", "name": {"en": "Gemini"}, "version": "0.1.0",
             "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": \(capabilities),
             "providers": [{"id": "dev.example.gemini.terminal", "capability": "agent.terminal", "name": "Gemini"}]
             \(terminal.map { ", \"terminal\": \($0)" } ?? "")}
            """
        return try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    @Test("A terminal plugin decodes with its icon and environment, on either transport")
    func valid() throws {
        let plugin = try manifest(#"{"icon": "sparkles", "environment": ["GEMINI_*", "GOOGLE_API_KEY"]}"#)
        try plugin.validate()
        #expect(plugin.terminal?.symbol == "sparkles")
        #expect(plugin.terminal?.environment == ["GEMINI_*", "GOOGLE_API_KEY"])
        #expect(try manifest("{}").terminal?.symbol == "terminal")
    }

    @Test("agent.terminal needs API 5 and the terminal object, and the object needs the capability")
    func pairing() throws {
        #expect(throws: PluginError.self) { try manifest("{}", apiVersion: 4).validate() }
        #expect(throws: PluginError.self) { try manifest(nil).validate() }
        #expect(throws: PluginError.self) { try manifest("{}", capabilities: #"["audio.beats"]"#).validate() }
    }

    @Test("The environment cannot reach BashCut's variables, PATH or everything")
    func environment() throws {
        for name in ["BASHCUT_SESSION_TOKEN", "BASHCUT_*", "PATH", "*", "A B", "1X"] {
            #expect(throws: PluginError.self) { try manifest(#"{"environment": ["\#(name)"]}"#).validate() }
        }
        let many = (0..<33).map { "\"V\($0)\"" }.joined(separator: ",")
        #expect(throws: PluginError.self) { try manifest(#"{"environment": [\#(many)]}"#).validate() }
        #expect(throws: PluginError.self) { try manifest(#"{"icon": "../x"}"#).validate() }
    }
}
