import BashCutPlugin
import Foundation
import Testing

struct PluginCatalogTests {
    @Test("Loudness results validate and normalization respects true-peak headroom")
    func loudnessResults() throws {
        let measured = try LoudnessMeasurement(result: .object([
            "integratedLUFS": .number(-20), "truePeakDbTP": .number(-3),
            "loudnessRangeLU": .number(7.5),
        ]))
        #expect(try LoudnessNormalizer.correction(measurement: measured) == 2)
        let quiet = LoudnessMeasurement(integratedLUFS: -24, truePeakDbTP: -20)
        #expect(try LoudnessNormalizer.correction(measurement: quiet) == 10)
        #expect(throws: PluginError.self) {
            try LoudnessMeasurement(result: .object([
                "integratedLUFS": .number(.nan), "truePeakDbTP": .integer(-1),
            ]))
        }
    }

    @Test("A loudness curve is optional and checked")
    func loudnessCurve() throws {
        let measured = try LoudnessMeasurement(result: .object([
            "integratedLUFS": .number(-20), "truePeakDbTP": .number(-3),
            "curve": .object(["step": .number(0.1), "momentary": .array([.number(-100), .number(-21.5)]),
                              "peakDb": .array([.number(-100), .number(-6)])]),
        ]))
        #expect(measured.curve?.momentary == [-100, -21.5] && measured.curve?.shortTerm == [])
        #expect(measured.json.object["curve"]?.object["step"] == .number(0.1))
        #expect(throws: PluginError.self) {
            try LoudnessMeasurement(result: .object([
                "integratedLUFS": .number(-20), "truePeakDbTP": .number(-3),
                "curve": .object(["step": .number(0), "momentary": .array([])]),
            ]))
        }
    }

    @Test("Voice synthesis accepts scored take arrays and legacy single outputs")
    func voiceSynthesisResults() throws {
        let takes = try VoiceSynthesisResultParser.parse(.object([
            "takes": .array([
                .object(["audioPath": .string("one.wav"), "score": .number(0.91)]),
                .object(["audioPath": .string("two.wav"), "score": .integer(1)]),
            ])
        ]))
        #expect(takes == [
            VoiceSynthesisTakeSpec(audioPath: "one.wav", score: 0.91),
            VoiceSynthesisTakeSpec(audioPath: "two.wav", score: 1),
        ])
        #expect(
            try VoiceSynthesisResultParser.parse(.object(["audioPath": .string("legacy.wav")]))
                == [VoiceSynthesisTakeSpec(audioPath: "legacy.wav")])
        #expect(throws: PluginError.self) {
            try VoiceSynthesisResultParser.parse(.object([
                "takes": .array([
                    .object(["audioPath": .string("same.wav")]),
                    .object(["audioPath": .string("same.wav")]),
                ])
            ]))
        }
        #expect(throws: PluginError.self) {
            try VoiceSynthesisResultParser.parse(.object([
                "audioPath": .string("bad.wav"), "score": .number(1.1),
            ]))
        }
    }

    @Test("Plugin manifests expose optional capabilities and argv-only install plans")
    func manifest() throws {
        let manifest = PluginManifest(
            id: "app.bashcut.whisper", name: "Whisper Transcription", version: "1.2.0",
            entrypoint: "bin/provider", capabilities: ["captions.transcribe"],
            dependencies: [
                PluginDependency(
                    id: "whisper-model", name: "Whisper model", kind: .model,
                    probe: PluginCommand(executable: "bin/provider", arguments: ["doctor"]),
                    install: PluginInstallRecipe(
                        summary: "Download the selected model",
                        command: PluginCommand(executable: "bin/provider", arguments: ["install-model"])),
                    estimatedBytes: 500_000_000),
            ])
        try manifest.validate()
        #expect(manifest.capabilities == ["captions.transcribe"])
    }

    @Test("Discovery isolates malformed bundles and keeps root precedence")
    func discovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = root.appendingPathComponent("good")
        let bad = root.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: good.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        let executable = good.appendingPathComponent("bin/provider")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let manifest = PluginManifest(
            id: "app.bashcut.beats", name: "Beat Detection", version: "1.0.0",
            entrypoint: "bin/provider", capabilities: ["audio.beats"])
        try JSONEncoder().encode(manifest).write(to: good.appendingPathComponent("plugin.json"))
        try Data("{broken".utf8).write(to: bad.appendingPathComponent("plugin.json"))

        let result = PluginCatalog.discover(in: [root])
        #expect(result.plugins.map(\.id) == ["app.bashcut.beats"])
        #expect(result.diagnostics.count == 1)
    }

    @Test("A bundled plugin wins over an older user copy, but not over a newer one")
    func bundledPrecedence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func install(_ folder: String, version: String) throws -> URL {
            let directory = root.appendingPathComponent(folder)
            let plugin = directory.appendingPathComponent("audio")
            try FileManager.default.createDirectory(at: plugin.appendingPathComponent("bin"), withIntermediateDirectories: true)
            let executable = plugin.appendingPathComponent("bin/provider")
            try Data("#!/bin/sh\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let manifest = PluginManifest(
                id: "bashcut.audio-analysis", name: "Audio", version: version, entrypoint: "bin/provider",
                capabilities: ["audio.beats"])
            try JSONEncoder().encode(manifest).write(to: plugin.appendingPathComponent("plugin.json"))
            return directory
        }
        let bundled = try install("bundled", version: "1.2.0")
        let olderUser = try install("user-old", version: "1.1.0")
        let newerUser = try install("user-new", version: "1.3.0")
        let stale = PluginCatalog.discover(in: [olderUser, bundled], bundled: bundled)
        #expect(stale.plugins.first?.manifest.version == "1.2.0")
        let hotfix = PluginCatalog.discover(in: [newerUser, bundled], bundled: bundled)
        #expect(hotfix.plugins.first?.manifest.version == "1.3.0")
        // Without a bundled root, the earlier root wins as before.
        #expect(PluginCatalog.discover(in: [olderUser, bundled]).plugins.first?.manifest.version == "1.1.0")
    }

    @Test("Entrypoints cannot escape a plugin bundle")
    func traversal() {
        let manifest = PluginManifest(
            id: "app.bashcut.bad", name: "Bad", version: "1.0.0", entrypoint: "../tool",
            capabilities: ["audio.bad"])
        #expect(throws: PluginError.self) { try manifest.validate() }
    }

    @Test("Provider resolution supports project override, user default and priority fallback")
    func providerResolution() {
        func plugin(_ id: String, provider: String, priority: Int) -> InstalledPlugin {
            InstalledPlugin(
                manifest: PluginManifest(
                    id: id, name: LocalizedText(["en": id]), version: "1.0.0", entrypoint: "bin/provider",
                    capabilities: ["voice.synthesize"],
                    providers: [
                        PluginProvider(
                            id: provider, capability: "voice.synthesize", name: provider,
                            priority: priority),
                    ]),
                directory: URL(fileURLWithPath: "/tmp/\(id)"))
        }
        let local = plugin("app.bashcut.local", provider: "local.voice", priority: 5)
        let cloud = plugin("app.bashcut.cloud", provider: "cloud.voice", priority: 10)
        let available: Set<String> = ["local.voice", "cloud.voice"]
        #expect(
            PluginProviderResolver.resolve(
                capability: "voice.synthesize", projectPreference: "local.voice",
                userPreference: "cloud.voice", plugins: [local, cloud],
                availableProviderIDs: available)?.provider.id == "local.voice")
        #expect(
            PluginProviderResolver.resolve(
                capability: "voice.synthesize", projectPreference: "missing.voice",
                userPreference: nil, plugins: [local, cloud], availableProviderIDs: available
            )?.provider.id == "cloud.voice")
    }

    @Test("Plugin runtime exchanges bounded JSON without inheriting secret environment values")
    func processRuntime() async throws {
        let fixture = try makeRuntimePlugin()
        defer { try? FileManager.default.removeItem(at: fixture.directory.deletingLastPathComponent()) }
        let result = try await PluginProcessRunner(timeout: 10, inheritedEnvironment: [
            "PATH": "/usr/bin:/bin", "BASHCUT_TEST_SECRET": "must-not-leak"
        ]).call(
            plugin: fixture, method: "voice.synthesize", provider: "fixture.voice",
            params: .object(["text": .string("xin chào")]))
        #expect(result.object["ok"] == .bool(true))
        #expect(result.object["argument"] == .string("rpc"))
        #expect(result.object["secret"] == .string("unset"))
        #expect(result.object["plugin"] == .string("app.bashcut.fixture"))
    }

    @Test("Plugin health reports available and installable missing dependencies")
    func healthProbe() async throws {
        let fixture = try makeRuntimePlugin(includeMissingDependency: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory.deletingLastPathComponent()) }

        let health = await PluginProcessRunner(timeout: 10).health(plugin: fixture)
        #expect(health.state == .degraded)
        #expect(health.dependencies.map(\.state) == [.available, .missing])
    }

    @Test("Plugin runtime rejects mismatched response ids")
    func responseIdentity() async throws {
        let fixture = try makeRuntimePlugin(fixedResponseID: "wrong-id")
        defer { try? FileManager.default.removeItem(at: fixture.directory.deletingLastPathComponent()) }
        await #expect(throws: PluginError.self) {
            try await PluginProcessRunner(timeout: 10).call(plugin: fixture, method: "fixture.run")
        }
    }

    private func makeRuntimePlugin(
        includeMissingDependency: Bool = false, fixedResponseID: String? = nil
    ) throws -> InstalledPlugin {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("provider.sh")
        let responseIDOverride = fixedResponseID.map { "id='\($0)'" } ?? ""
        let script = """
            #!/bin/sh
            if [ "${1:-}" = "doctor" ]; then exit 0; fi
            input=$(cat)
            id=$(printf '%s' "$input" | sed -E 's/.*"id":"([^"]+)".*/\\1/')
            \(responseIDOverride)
            printf '{"id":"%s","result":{"ok":true,"argument":"%s","secret":"%s","plugin":"%s"}}\\n' \
              "$id" "${1:-}" "${BASHCUT_TEST_SECRET:-unset}" "${BASHCUT_PLUGIN_ID:-missing}"
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var dependencies = [
            PluginDependency(
                id: "provider", name: "Fixture provider", kind: .executable,
                probe: PluginCommand(executable: "./provider.sh", arguments: ["doctor"]))
        ]
        if includeMissingDependency {
            dependencies.append(
                PluginDependency(
                    id: "optional-model", name: "Optional model", kind: .model,
                    probe: PluginCommand(executable: "missing-provider", arguments: ["doctor"]),
                    install: PluginInstallRecipe(
                        summary: "Install fixture model",
                        command: PluginCommand(executable: "./provider.sh", arguments: ["install"]))))
        }
        let manifest = PluginManifest(
            id: "app.bashcut.fixture", name: "Fixture", version: "1.0.0",
            entrypoint: "provider.sh", capabilities: ["voice.synthesize"],
            providers: [
                PluginProvider(
                    id: "fixture.voice", capability: "voice.synthesize", name: "Fixture Voice")
            ], dependencies: dependencies)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        return InstalledPlugin(manifest: manifest, directory: directory)
    }

    @Test("A catalog cache reuses unchanged plugins and reads changed, new and removed ones again")
    func catalogCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ id: String, name: String) throws {
            let directory = root.appendingPathComponent(id)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
            let manifest = PluginManifest(
                id: id, name: LocalizedText(["en": name]), version: "1.0.0", entrypoint: "bin/provider",
                capabilities: ["audio.beats"])
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
            let entrypoint = directory.appendingPathComponent("bin/provider")
            try Data("#!/bin/sh\n".utf8).write(to: entrypoint)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
        }
        try write("example.a", name: "A")
        try write("example.b", name: "B")
        let cache = PluginCatalogCache()
        func names() -> [String] {
            PluginCatalog.discover(in: [root], cache: cache).plugins.map(\.manifest.displayName)
        }
        #expect(names() == ["A", "B"])
        #expect(names() == ["A", "B"])
        try write("example.a", name: "A renamed")
        try write("example.c", name: "C")
        #expect(names() == ["A renamed", "B", "C"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("example.b"))
        #expect(names() == ["A renamed", "C"])
        // An entrypoint that is no longer executable is reported again, not served from the cache.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("example.c/bin/provider").path)
        let result = PluginCatalog.discover(in: [root], cache: cache)
        #expect(result.plugins.map(\.id) == ["example.a"])
        #expect(result.diagnostics.contains { $0.contains("example.c") })
    }
}
