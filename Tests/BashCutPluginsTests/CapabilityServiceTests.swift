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
    @Test("The App Store channel searches only the plugins inside the app")
    func channelRoots() {
        let user = URL(fileURLWithPath: "/tmp/user")
        let bundled = URL(fileURLWithPath: "/tmp/app/PlugIns")
        let project = URL(fileURLWithPath: "/tmp/project")
        let direct = PluginRoots(user: user, bundled: bundled)
        #expect(direct.ordered(projectRoot: project).map(\.lastPathComponent) == ["plugins", "user", "PlugIns"])
        let store = PluginRoots(user: user, bundled: bundled, includesUserPlugins: false)
        #expect(store.ordered(projectRoot: project) == [bundled])
        #expect(PluginChannel.direct.allowsUserPlugins && !PluginChannel.appStore.allowsUserPlugins)
    }

    @Test("Transcription returns confined SRT text with plugin provenance")
    func transcribe() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.captions", providers: [PluginProvider(id: "test.whisper", capability: "captions.transcribe", name: "W")],
            body: """
                printf '1\\n00:00:00,000 --> 00:00:01,000\\nXin chào\\n' > "$out/captions.srt"
                printf '[{"text":"Xin","start":0.1,"end":0.4},{"text":"chào","start":0.4,"end":0.9}]' > "$out/words.json"
                printf '{"id":"%s","result":{"srtPath":"captions.srt","wordsPath":"words.json"}}\\n' "$id"
                """)
        let generated = try await sandbox.service.transcribe(
            mediaURL: try sandbox.media(), language: "vi", preferredProvider: nil, projectRoot: sandbox.project,
            outputRoot: sandbox.project.appendingPathComponent("subtitles/generated"))
        #expect(generated.text.contains("Xin chào"))
        #expect(generated.provenance == PluginProvenance(pluginID: "test.captions", pluginVersion: "2.1.0", providerID: "test.whisper"))
        #expect(generated.provenance.json["provider"] == .string("test.whisper"))
        #expect(generated.words.map(\.text) == ["Xin", "chào"])
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

    @Test("Loudness with bands asks for them and reads the band shares; bad shares are refused")
    func loudnessBands() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let transport = RecordingTransport(result: .object([
            "integratedLUFS": .number(-20), "truePeakDbTP": .number(-3), "loudnessRangeLU": .number(2),
            "speechShare": .number(0.21), "presenceShare": .number(0.009),
        ]))
        try sandbox.addPlugin(
            "test.loudness", providers: [PluginProvider(id: "test.r128", capability: "audio.loudness", name: "R")],
            body: "exit 1")
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        let media = try sandbox.media()
        let measured = try await service.analyzeLoudness(
            mediaURL: media, bands: true, preferredProvider: nil, projectRoot: sandbox.project)
        #expect(measured.measurement.presenceShare == 0.009)
        #expect(measured.measurement.speechShare == 0.21)
        #expect(await transport.calls.last?.params.object["bands"] == .bool(true))
        _ = try await service.analyzeLoudness(mediaURL: media, preferredProvider: nil, projectRoot: sandbox.project)
        #expect(await transport.calls.last?.params.object["bands"] == nil)
        #expect(throws: PluginError.self) {
            try LoudnessMeasurement(result: .object([
                "integratedLUFS": .number(-20), "truePeakDbTP": .number(-3), "presenceShare": .number(1.5),
            ]))
        }
    }

    @Test("Sync results carry the offset, the halves and whether they agree; malformed ones are refused")
    func sync() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.sync", providers: [PluginProvider(id: "test.sync.provider", capability: "audio.sync", name: "S")],
            body: #"""
                halves='[{"offsetSeconds":2.49,"correlation":0.8},{"offsetSeconds":2.5,"correlation":0.77}]'
                overlap='"overlapStartSeconds":0,"overlapEndSeconds":280'
                printf '{"id":"%s","result":{"offsetSeconds":2.49,"correlation":0.79,%s,"halves":%s}}\n' "$id" "$overlap" "$halves"
                """#)
        let first = try sandbox.media("camera.wav"), second = try sandbox.media("screen.wav")
        let result = try await sandbox.service.syncAudio(
            mediaURL: first, otherURL: second, preferredProvider: nil, projectRoot: sandbox.project)
        #expect(result.match == GeneratedAudioSync.Match(offsetSeconds: 2.49, correlation: 0.79))
        #expect(result.halves.count == 2 && result.isSteady)
        #expect(result.overlap == 0...280)
        #expect(result.provenance.providerID == "test.sync.provider")

        let transport = RecordingTransport(result: .object(["offsetSeconds": .string("soon")]))
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        await #expect(throws: PluginError.self) {
            try await service.syncAudio(mediaURL: first, otherURL: second, preferredProvider: nil, projectRoot: sandbox.project)
        }
        let params = await transport.calls.last?.params.object
        #expect(params?["mediaPath"] == .string(first.path) && params?["otherPath"] == .string(second.path))
    }

    @Test("A transcription range is sent as startSeconds and endSeconds")
    func transcriptionRange() {
        let capability = TranscriptionCapability(
            mediaURL: URL(fileURLWithPath: "/tmp/a.wav"), language: "vi", outputRoot: URL(fileURLWithPath: "/tmp"),
            range: 128...148.5)
        let params = capability.params(outputDirectory: nil).object
        #expect(params["startSeconds"] == .number(128) && params["endSeconds"] == .number(148.5))
        let whole = TranscriptionCapability(
            mediaURL: URL(fileURLWithPath: "/tmp/a.wav"), language: "vi", outputRoot: URL(fileURLWithPath: "/tmp"))
        #expect(whole.params(outputDirectory: nil).object["startSeconds"] == nil)
    }

    @Test("Provider-backed automation commands are catalogued with their permission modes")
    func commandModes() {
        #expect(CommandCatalog.modes["plugins.list"] == .read)
        #expect(CommandCatalog.modes["jobs.status"] == .read)
        #expect(CommandCatalog.modes["audio.measure"] == .read)
        #expect(CommandCatalog.modes["media.sync"] == .read)
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

    @Test("Capability requests carry the plugin's option values")
    func providerOptions() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.echo", providers: [PluginProvider(id: "test.echo.provider", capability: "text.echo", name: "Echo")],
            body: "exit 1")
        let transport = RecordingTransport(result: .object(["text": .string("ok")]))
        var service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        _ = try await service.run(EchoCapability(text: "a"), preferredProvider: nil, projectRoot: sandbox.project)
        #expect(await transport.calls.last?.params.object["options"] == nil)
        service.optionValues = { plugin in ["voice": .string("Mai Anh"), "plugin": .string(plugin.id)] }
        _ = try await service.run(EchoCapability(text: "b"), preferredProvider: nil, projectRoot: sandbox.project)
        let options = await transport.calls.last?.params.object["options"]
        #expect(options == .object(["voice": .string("Mai Anh"), "plugin": .string("test.echo")]))
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
