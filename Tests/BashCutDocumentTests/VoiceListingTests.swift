import BashCutDocument
import BashCutPlugin
import BashCutProject
import BashCutStorage
import Foundation
import Testing

/// Preset and clone labels in `capabilities get --voices` (#532).
struct VoiceListingTests {
    private func provider(clones: Bool, clone: PluginCloneRange? = nil) throws -> PluginProvider {
        var provider = PluginProvider(id: "vieneu.local", capability: "voice.synthesize", name: "VieNeu")
        provider.voices = try JSONDecoder().decode([PluginVoice].self, from: Data(#"[{"id": "Hải Đăng", "language": "vi"}]"#.utf8))
        provider.clones = clones
        provider.clone = clone
        return provider
    }

    private func clone(_ id: String, seconds: Double) -> VoiceClone {
        VoiceClone(
            id: id, name: "Giọng Nolan", language: "vi", providers: ["vieneu.local"], sourceDescription: "a.wav",
            durationSeconds: seconds, consent: .init(by: "user", statement: .own), reference: "reference.wav")
    }

    @Test("Clones the provider can use come first as kind clone from my-voices; presets are kind preset from the provider")
    func kinds() throws {
        let rows = VoiceListing.rows(
            provider: try provider(clones: true), clones: [clone("clone-nolan", seconds: 6), clone("clone-long", seconds: 20)],
            rates: [], content: "vi"
        ).map(\.object)
        #expect(rows.map { $0["id"]?.string } == ["clone-nolan", "Hải Đăng"])
        #expect(rows[0]["kind"] == .string("clone") && rows[0]["source"] == .string("my-voices"))
        #expect(rows[0]["name"] == .string("Giọng Nolan") && rows[0]["speaksContentLanguage"] == .bool(true))
        #expect(rows[1]["kind"] == .string("preset") && rows[1]["source"] == .string("vieneu.local"))
    }

    @Test("A provider that does not clone lists no clones; a declared range decides which clones fit")
    func cloneRanges() throws {
        let clones = [clone("clone-nolan", seconds: 6), clone("clone-long", seconds: 20)]
        let presetsOnly = VoiceListing.rows(provider: try provider(clones: false), clones: clones, rates: [], content: "")
        #expect(presetsOnly.map { $0.object["kind"] } == [.string("preset")])
        let wide = try provider(clones: true, clone: PluginCloneRange(minSeconds: 10, maxSeconds: 30))
        let rows = VoiceListing.rows(provider: wide, clones: clones, rates: [], content: "")
        #expect(rows.compactMap { $0.object["kind"] == .string("clone") ? $0.object["id"]?.string : nil } == ["clone-long"])
    }
}
