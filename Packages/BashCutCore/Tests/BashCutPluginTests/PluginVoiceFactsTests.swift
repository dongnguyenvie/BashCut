import BashCutPlugin
import Foundation
import Testing

/// Voice facts and cloning on `voice.synthesize` providers (P0-C7).
@Suite("Plugin voice facts")
struct PluginVoiceFactsTests {
    private func manifest(capability: String, provider: String) throws -> PluginManifest {
        let json = """
            {"schema": "bashcut.plugin/1", "id": "example.voice", "name": "Voice", "version": "1.0.0",
             "apiVersion": 2, "entrypoint": "bin/provider", "capabilities": ["\(capability)"],
             "providers": [{"id": "example.voice.local", "capability": "\(capability)", "name": "Local"\(provider)}]}
            """
        return try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    @Test("Voices decode with their facts; cloning is a provider flag")
    func voices() throws {
        let voice = try manifest(
            capability: "voice.synthesize",
            provider: #", "clones": true, "voices": [{"id": "Mai Anh", "language": "vi", "region": "North", "style": "news", "#
                + #""gender": "female", "supportsRate": false}]"#)
        try voice.validate()
        let provider = try #require(voice.providers?.first)
        #expect(provider.clones == true && provider.voices?.first?.region == "North")
        #expect(provider.voices?.first?.supportsRate == false)
    }

    @Test("Voices off voice.synthesize, duplicate IDs or a missing language are refused")
    func invalid() throws {
        let other = try manifest(capability: "audio.beats", provider: #", "voices": [{"id": "a", "language": "vi"}]"#)
        #expect(throws: PluginError.self) { try other.validate() }
        let duplicate = try manifest(
            capability: "voice.synthesize", provider: #", "voices": [{"id": "a", "language": "vi"}, {"id": "a", "language": "vi"}]"#)
        #expect(throws: PluginError.self) { try duplicate.validate() }
        let blank = try manifest(capability: "voice.synthesize", provider: #", "voices": [{"id": "a", "language": ""}]"#)
        #expect(throws: PluginError.self) { try blank.validate() }
    }
}
