import AVFoundation
import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutAutomation
@testable import BashCutPlugins

/// A temporary project with fake shell plugins. Nothing touches the user's catalog, models or network.
private struct PluginSandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("capability-\(UUID().uuidString)")
    var project: URL { root.appendingPathComponent("project", isDirectory: true) }
    var service: CapabilityService {
        CapabilityService(
            roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil),
            transport: PluginProcessRunner(timeout: 10), healthTransport: PluginProcessRunner(timeout: 5))
    }

    init() throws {
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    /// `body` runs after `$id`, `$out` (request output directory) and `$provider` are parsed from the request.
    func addPlugin(
        _ id: String, providers: [PluginProvider], body: String, healthy: Bool = true, userScope: Bool = false
    ) throws {
        let directory = (userScope ? root.appendingPathComponent("user") : project.appendingPathComponent(".bashcut/plugins"))
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = """
            #!/bin/sh
            input=$(cat)
            id=$(printf '%s' "$input" | sed -E 's/.*"id":"([^"]+)".*/\\1/')
            out=$(printf '%s' "$input" | sed -E 's/.*"outputDirectory":"([^"]+)".*/\\1/' | sed 's#\\\\/#/#g')
            provider=$(printf '%s' "$input" | sed -E 's/.*"provider":"([^"]+)".*/\\1/')
            \(body)
            """
        let entrypoint = directory.appendingPathComponent("provider.sh")
        try Data(script.utf8).write(to: entrypoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        let dependencies = healthy ? [] : [
            PluginDependency(
                id: "model", name: "Missing model", kind: .model,
                probe: PluginCommand(executable: "bashcut-test-missing-binary")),
        ]
        let manifest = PluginManifest(
            id: id, name: LocalizedText(["en": id]), version: "2.1.0", entrypoint: "provider.sh",
            capabilities: Array(Set(providers.map(\.capability))), providers: providers,
            dependencies: dependencies)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
    }

    func media(_ name: String = "source.wav") throws -> URL {
        let url = project.appendingPathComponent(name)
        try TestFixtures.writeTone(to: url, seconds: 0.5)
        return url
    }
}

@Suite("Capability service")
struct CapabilityServiceTests {
    @Test("Transcription returns confined SRT text with plugin provenance")
    func transcribe() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.captions", providers: [PluginProvider(id: "test.whisper", capability: "captions.transcribe", name: "W")],
            body: """
                printf '1\\n00:00:00,000 --> 00:00:01,000\\nXin chào\\n' > "$out/captions.srt"
                printf '{"id":"%s","result":{"srtPath":"captions.srt"}}\\n' "$id"
                """)
        let generated = try await sandbox.service.transcribe(
            mediaURL: try sandbox.media(), language: "vi", preferredProvider: nil, projectRoot: sandbox.project,
            outputRoot: sandbox.project.appendingPathComponent("subtitles/generated"))
        #expect(generated.text.contains("Xin chào"))
        #expect(generated.provenance == PluginProvenance(pluginID: "test.captions", pluginVersion: "2.1.0", providerID: "test.whisper"))
        #expect(generated.provenance.json["provider"] == .string("test.whisper"))
    }

    @Test("Output outside the request directory is rejected and the request folder removed")
    func confinement() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.captions", providers: [PluginProvider(id: "test.escape", capability: "captions.transcribe", name: "E")],
            body: """
                printf 'x' > "$out/../escaped.srt"
                printf '{"id":"%s","result":{"srtPath":"../escaped.srt"}}\\n' "$id"
                """)
        let outputRoot = sandbox.project.appendingPathComponent("subtitles/generated")
        await #expect(throws: PluginError.self) {
            try await sandbox.service.transcribe(
                mediaURL: try sandbox.media(), language: "vi", preferredProvider: nil,
                projectRoot: sandbox.project, outputRoot: outputRoot)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outputRoot.path)
        #expect(leftovers == ["escaped.srt"])
    }

    @Test("Resolution honors the project preference, then priority, and skips unhealthy providers")
    func resolution() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let beats = #"printf '{"id":"%s","result":{"bpm":%s,"beatsSeconds":[0.1,0.6]}}\n' "$id" "$BPM""#
        try sandbox.addPlugin(
            "test.fast", providers: [PluginProvider(id: "fast", capability: "audio.beats", name: "F", priority: 10)],
            body: "BPM=120\n" + beats)
        try sandbox.addPlugin(
            "test.slow", providers: [PluginProvider(id: "slow", capability: "audio.beats", name: "S")],
            body: "BPM=90\n" + beats, userScope: true)
        let media = try sandbox.media()
        let byPriority = try await sandbox.service.detectBeats(
            mediaURL: media, preferredProvider: nil, projectRoot: sandbox.project)
        #expect(byPriority.bpm == 120)
        let preferred = try await sandbox.service.detectBeats(
            mediaURL: media, preferredProvider: "slow", projectRoot: sandbox.project)
        #expect(preferred.bpm == 90)
        #expect(preferred.provenance.providerID == "slow")

        try FileManager.default.removeItem(at: sandbox.project.appendingPathComponent(".bashcut/plugins/test.fast"))
        try sandbox.addPlugin(
            "test.fast", providers: [PluginProvider(id: "fast", capability: "audio.beats", name: "F", priority: 10)],
            body: "BPM=120\n" + beats, healthy: false)
        let fallback = try await sandbox.service.detectBeats(
            mediaURL: media, preferredProvider: "fast", projectRoot: sandbox.project)
        #expect(fallback.bpm == 90)
    }

    @Test("Missing providers and invalid beat results fail at the service boundary")
    func failures() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let media = try sandbox.media()
        await #expect(throws: PluginError.invalid("Install a plugin that provides audio.beats")) {
            try await sandbox.service.detectBeats(mediaURL: media, preferredProvider: nil, projectRoot: sandbox.project)
        }
        try sandbox.addPlugin(
            "test.beats", providers: [PluginProvider(id: "bad", capability: "audio.beats", name: "B")],
            body: #"printf '{"id":"%s","result":{"bpm":120,"beatsSeconds":[1.0,0.5]}}\n' "$id""#)
        await #expect(throws: PluginError.self) {
            try await sandbox.service.detectBeats(mediaURL: media, preferredProvider: nil, projectRoot: sandbox.project)
        }
    }

    @Test("Voice takes are validated audio, scored, and discardable while keeping the chosen take")
    func voiceTakes() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let tone = sandbox.root.appendingPathComponent("tone.wav")
        try TestFixtures.writeTone(to: tone, seconds: 1)
        try sandbox.addPlugin(
            "test.voice", providers: [PluginProvider(id: "test.tts", capability: "voice.synthesize", name: "T")],
            body: """
                cp '\(tone.path)' "$out/a.wav"
                cp '\(tone.path)' "$out/b.wav"
                printf '{"id":"%s","result":{"takes":[{"audioPath":"a.wav","score":0.4},{"audioPath":"b.wav","score":0.9}]}}\\n' "$id"
                """)
        let takes = try await sandbox.service.synthesizeVoiceTakes(
            text: "Xin chào các bạn", language: "vi", count: 2, preferredProvider: nil,
            projectRoot: sandbox.project, outputRoot: sandbox.project.appendingPathComponent("voiceover/generated"))
        #expect(takes.count == 2)
        #expect(takes.allSatisfy { $0.scoreSource == "provider" && abs($0.durationSeconds - 1) < 0.05 })
        let best = try #require(takes.best)
        #expect(best.score == 0.9)
        CapabilityService.discardVoiceTakes(takes, keeping: best.asset.url)
        #expect(FileManager.default.fileExists(atPath: best.asset.url.path))
        #expect(takes.filter { $0.id != best.id }.allSatisfy { !FileManager.default.fileExists(atPath: $0.asset.url.path) })
    }

    @Test("Loudness measurements carry provenance")
    func loudness() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.loudness", providers: [PluginProvider(id: "test.r128", capability: "audio.loudness", name: "R")],
            body: #"printf '{"id":"%s","result":{"integratedLUFS":-16.5,"truePeakDbTP":-2.0}}\n' "$id""#)
        let measured = try await sandbox.service.analyzeLoudness(
            mediaURL: try sandbox.media(), preferredProvider: nil, projectRoot: sandbox.project)
        #expect(measured.measurement == LoudnessMeasurement(integratedLUFS: -16.5, truePeakDbTP: -2))
        #expect(measured.provenance.providerID == "test.r128")
    }

    @Test("Provider-backed automation commands are catalogued with their permission modes")
    func commandModes() {
        #expect(CommandCatalog.modes["plugins.list"] == .read)
        #expect(CommandCatalog.modes["jobs.status"] == .read)
        for method in ["captions.generate", "beats.detect", "voice.speak", "jobs.cancel"] {
            #expect(CommandCatalog.modes[method] == .edit)
        }
        #expect(CommandCatalog.instructions.contains("bashcut voice speak"))
    }
}

/// Answers every call with `result` and records what it was asked; every plugin reports ready.
private actor RecordingTransport: PluginTransport {
    let result: JSONValue
    private(set) var calls: [(method: String, provider: String?, params: JSONValue)] = []

    init(result: JSONValue) { self.result = result }

    func call(plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue) async throws -> JSONValue {
        calls.append((method, provider, params))
        return result
    }

    nonisolated func health(plugin: InstalledPlugin) async -> PluginHealth {
        PluginHealth(pluginID: plugin.id, state: .ready, dependencies: [])
    }
}

/// A capability defined only in this test: the service needs nothing else to run it.
private struct EchoCapability: CapabilityAdapter {
    static let capability = "text.echo"
    let text: String
    var outputRoot: URL?

    func validate() throws {
        guard !text.isEmpty else { throw PluginError.invalid("Text is required") }
    }

    func params(outputDirectory: URL?) -> JSONValue {
        .object(["text": .string(text), "outputDirectory": .string(outputDirectory?.path ?? "")])
    }

    func output(from result: JSONValue, context: CapabilityContext) async throws -> String {
        guard let echoed = result.object["text"]?.string else { throw PluginError.invalid("No text") }
        return echoed + " via " + context.provenance.providerID
    }
}

@Suite("Capability adapters")
struct CapabilityAdapterTests {
    @Test("A new capability is one adapter: the service resolves a provider and calls the transport")
    func customAdapter() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.echo", providers: [PluginProvider(id: "test.echo.provider", capability: "text.echo", name: "Echo")],
            body: "exit 1")
        let transport = RecordingTransport(result: .object(["text": .string("xin chào")]))
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        let output = try await service.run(EchoCapability(text: "hello"), preferredProvider: nil, projectRoot: sandbox.project)
        #expect(output == "xin chào via test.echo.provider")
        let calls = await transport.calls
        #expect(calls.count == 1)
        #expect(calls.first?.method == "text.echo")
        #expect(calls.first?.provider == "test.echo.provider")
        await #expect(throws: PluginError.self) {
            try await service.run(EchoCapability(text: ""), preferredProvider: nil, projectRoot: sandbox.project)
        }
        #expect(await transport.calls.count == 1)
    }

    @Test("A rejected result removes the request folder")
    func requestFolderCleanup() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.echo", providers: [PluginProvider(id: "test.echo.provider", capability: "text.echo", name: "Echo")],
            body: "exit 1")
        let transport = RecordingTransport(result: .object([:]))
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        let outputRoot = sandbox.project.appendingPathComponent("generated")
        await #expect(throws: PluginError.self) {
            try await service.run(
                EchoCapability(text: "hello", outputRoot: outputRoot), preferredProvider: nil, projectRoot: sandbox.project)
        }
        let requested = await transport.calls.first?.params.object["outputDirectory"]?.string
        #expect(requested?.hasPrefix(outputRoot.path) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path).isEmpty)
    }
}
