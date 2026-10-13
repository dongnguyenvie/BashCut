import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutPlugins

/// What a `voice.synthesize` request carries for a preset or a saved clone (#532).
struct VoiceCloneWireTests {
    private let reference = VoiceCloneReference(
        path: "/tmp/Voices/clone-nolan/reference.wav", voice: "clone-nolan", name: "Giọng Nolan", language: "vi")

    @Test("A clone adds reference {path, voice, name, language} and cloneConsent; a preset is a voice option override")
    func params() {
        let output = URL(fileURLWithPath: "/tmp/out")
        let clone = VoiceSynthesisCapability(
            text: "Xin chào", language: "vi", takeCount: 1, outputRoot: output, voice: .clone(reference))
        let fields = clone.params(outputDirectory: output).object
        #expect(fields["cloneConsent"] == .bool(true))
        #expect(fields["reference"] == .object([
            "path": .string(reference.path), "voice": .string("clone-nolan"), "name": .string("Giọng Nolan"),
            "language": .string("vi"),
        ]))
        #expect(clone.optionOverrides.isEmpty)
        let preset = VoiceSynthesisCapability(
            text: "Xin chào", language: "vi", takeCount: 1, outputRoot: output, voice: .preset("Hải Đăng"))
        #expect(preset.params(outputDirectory: output).object["reference"] == nil)
        #expect(preset.params(outputDirectory: output).object["cloneConsent"] == .bool(false))
        #expect(preset.optionOverrides == ["voice": .string("Hải Đăng")])
    }

    @Test("A clone is never sent to a provider that does not clone; a cloning one gets the reference")
    func onlyCloningProviders() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let tone = sandbox.root.appendingPathComponent("tone.wav")
        let request = sandbox.root.appendingPathComponent("request.json")
        try TestFixtures.writeTone(to: tone, seconds: 1)
        let body = """
            printf '%s' "$input" > '\(request.path)'
            cp '\(tone.path)' "$out/a.wav"
            printf '{"id":"%s","result":{"audioPath":"a.wav"}}\\n' "$id"
            """
        try sandbox.addPlugin(
            "test.preset", providers: [PluginProvider(id: "test.preset", capability: "voice.synthesize", name: "Presets")],
            body: body)
        let output = sandbox.project.appendingPathComponent("voiceover/generated")
        await #expect(throws: PluginError.self) {
            _ = try await sandbox.service.synthesizeVoiceTakes(
                text: "Xin chào", language: "vi", count: 1, preferredProvider: "test.preset", projectRoot: sandbox.project,
                outputRoot: output, voice: .clone(reference))
        }
        #expect(!FileManager.default.fileExists(atPath: request.path))
        var cloning = PluginProvider(id: "test.clone", capability: "voice.synthesize", name: "Clones")
        cloning.clones = true
        try sandbox.addPlugin("test.clone", providers: [cloning], body: body)
        let takes = try await sandbox.service.synthesizeVoiceTakes(
            text: "Xin chào", language: "vi", count: 1, preferredProvider: "test.clone", projectRoot: sandbox.project,
            outputRoot: output, voice: .clone(reference))
        #expect(takes.count == 1)
        let sent = try String(contentsOf: request, encoding: .utf8)
        #expect(sent.contains("\"reference\"") && sent.contains("clone-nolan"))
    }
}
