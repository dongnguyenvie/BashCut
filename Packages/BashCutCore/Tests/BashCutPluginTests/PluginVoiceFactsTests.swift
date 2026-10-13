import BashCutPlugin
import Foundation
import Testing

/// Voice facts and cloning on `voice.synthesize` providers (P0-C7).
@Suite("Plugin voice facts")
struct PluginVoiceFactsTests {
    private func manifest(capability: String, provider: String, apiVersion: Int = 2) throws -> PluginManifest {
        let json = """
            {"schema": "bashcut.plugin/1", "id": "example.voice", "name": "Voice", "version": "1.0.0",
             "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": ["\(capability)"],
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

    @Test("Paid and estimates are provider flags (P2-G4), absent by default, and survive encoding")
    func paid() throws {
        let plain = try #require(try manifest(capability: "voice.synthesize", provider: "").providers?.first)
        #expect(plain.paid == nil && plain.estimates == nil)
        let paid = try manifest(capability: "voice.synthesize", provider: #", "paid": true, "estimates": true"#)
        let provider = try #require(paid.providers?.first)
        #expect(provider.paid == true && provider.estimates == true)
        let again = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(paid))
        #expect(again.providers?.first == provider)
    }

    @Test("clone declares the reference range; clones: true alone means 3–8 s; checked and API 9 (#532)")
    func cloneRange() throws {
        let declared = try manifest(
            capability: "voice.synthesize", provider: #", "clone": {"minSeconds": 5, "maxSeconds": 12, "formats": ["wav"]}"#,
            apiVersion: 9)
        try declared.validate()
        let provider = try #require(declared.providers?.first)
        #expect(provider.cloneRange == PluginCloneRange(minSeconds: 5, maxSeconds: 12, formats: ["wav"]))
        #expect(provider.cloneRange?.accepts(6) == true && provider.cloneRange?.accepts(13) == false)
        let again = try JSONDecoder().decode(PluginManifest.self, from: JSONEncoder().encode(declared))
        #expect(again.providers?.first == provider)
        let legacy = try #require(try manifest(capability: "voice.synthesize", provider: #", "clones": true"#).providers?.first)
        #expect(legacy.cloneRange == .standard)
        #expect(try #require(try manifest(capability: "voice.synthesize", provider: "").providers?.first).cloneRange == nil)
        #expect(PluginFeature.all.contains("voice.savedClones"))
        for (capability, extra, api) in [
            ("voice.synthesize", #", "clone": {"minSeconds": 8, "maxSeconds": 3}"#, 9),
            ("voice.synthesize", #", "clone": {"minSeconds": 0.5, "maxSeconds": 3}"#, 9),
            ("voice.synthesize", #", "clone": {"minSeconds": 3, "maxSeconds": 61}"#, 9),
            ("voice.synthesize", #", "clones": false, "clone": {"minSeconds": 3, "maxSeconds": 8}"#, 9),
            ("audio.beats", #", "clone": {"minSeconds": 3, "maxSeconds": 8}"#, 9),
            ("voice.synthesize", #", "clone": {"minSeconds": 3, "maxSeconds": 8}"#, 8),
        ] {
            let manifest = try manifest(capability: capability, provider: extra, apiVersion: api)
            #expect(throws: PluginError.self) { try manifest.validate() }
        }
    }

    @Test("maxTakes caps the takes asked of a voice provider; 1–8, voice.synthesize, API 8 (#410)")
    func maxTakes() throws {
        let one = try manifest(capability: "voice.synthesize", provider: #", "maxTakes": 1"#, apiVersion: 8)
        try one.validate()
        let provider = try #require(one.providers?.first)
        #expect(provider.maxTakes == 1 && provider.takes(3) == 1)
        #expect(try #require(try manifest(capability: "voice.synthesize", provider: "").providers?.first).takes(3) == 3)
        #expect(PluginFeature.all.contains("voice.maxTakes"))
        for (capability, extra, api) in [("voice.synthesize", #", "maxTakes": 0"#, 8), ("voice.synthesize", #", "maxTakes": 9"#, 8),
                                         ("audio.beats", #", "maxTakes": 1"#, 8), ("voice.synthesize", #", "maxTakes": 1"#, 7)] {
            let manifest = try manifest(capability: capability, provider: extra, apiVersion: api)
            #expect(throws: PluginError.self) { try manifest.validate() }
        }
    }
}
