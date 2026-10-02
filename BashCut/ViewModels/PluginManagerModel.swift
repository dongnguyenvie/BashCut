import AppKit
import AVFoundation
import BashCutPlugin
import Foundation
import Observation

struct PendingPluginInstall: Identifiable {
    let id = UUID()
    let plugin: InstalledPlugin
}

struct PluginProviderChoice: Identifiable, Equatable {
    let pluginID: String
    let pluginName: String
    let provider: PluginProvider
    var id: String { provider.id }
}

struct GeneratedPluginAsset: Sendable {
    let url: URL
    let pluginID: String
    let pluginVersion: String
    let providerID: String
}

struct GeneratedVoiceTake: Identifiable, Sendable {
    let asset: GeneratedPluginAsset
    let durationSeconds: Double
    let score: Double
    let scoreSource: String
    var id: String { asset.url.path }
}

private struct VoiceSynthesisRequest {
    let text: String
    let language: String
    let requested: Int
    let takeOffset: Int
    let outputRoot: URL
}

struct GeneratedPluginCaptions: Sendable {
    let text: String
    let pluginID: String
    let pluginVersion: String
    let providerID: String
}

struct GeneratedBeatGrid: Sendable {
    let bpm: Double
    let beatSeconds: [Double]
    let pluginID: String
    let pluginVersion: String
    let providerID: String
}

struct GeneratedLoudnessMeasurement: Sendable {
    let measurement: LoudnessMeasurement
    let pluginID: String
    let pluginVersion: String
    let providerID: String
}

@MainActor @Observable final class PluginManagerModel {
    var plugins: [InstalledPlugin] = []
    var diagnostics: [String] = []
    var pendingInstall: PendingPluginInstall?
    var installing = false
    var message = ""
    var health: [String: PluginHealth] = [:]
    var checking: Set<String> = []
    var calling: Set<String> = []
    private var projectRoot: URL?
    private let runner = PluginProcessRunner()
    private let healthRunner = PluginProcessRunner(timeout: 15, maximumOutputBytes: 256 * 1024)

    private var userRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/Plugins", isDirectory: true)
    }

    func refresh(projectRoot: URL?) {
        self.projectRoot = projectRoot
        var roots: [URL] = []
        if let projectRoot { roots.append(projectRoot.appendingPathComponent(".bashcut/plugins")) }
        roots.append(userRoot)
        if let builtIn = Bundle.main.builtInPlugInsURL { roots.append(builtIn) }
        let result = PluginCatalog.discover(in: roots)
        plugins = result.plugins
        diagnostics = result.diagnostics
        health = health.filter { id, _ in plugins.contains(where: { $0.id == id }) }
    }

    func checkHealth(_ plugin: InstalledPlugin) {
        guard !checking.contains(plugin.id) else { return }
        checking.insert(plugin.id)
        Task {
            let result = await healthRunner.health(plugin: plugin)
            health[plugin.id] = result
            checking.remove(plugin.id)
        }
    }

    func providers(for capability: String) -> [PluginProviderChoice] {
        plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).compactMap { provider in
                guard provider.capability == capability else { return nil }
                return PluginProviderChoice(
                    pluginID: plugin.id, pluginName: plugin.manifest.name, provider: provider)
            }
        }.sorted {
            ($0.provider.priority, $0.provider.name) > ($1.provider.priority, $1.provider.name)
        }
    }

    func synthesizeVoice(
        text: String, language: String, preferredProvider: String?, outputRoot: URL
    ) async throws -> GeneratedPluginAsset {
        try await synthesizeVoiceTakes(
            text: text, language: language, count: 1,
            preferredProvider: preferredProvider, outputRoot: outputRoot
        )[0].asset
    }

    func synthesizeVoiceTakes(
        text: String, language: String, count: Int = 3,
        preferredProvider: String?, outputRoot: URL
    ) async throws -> [GeneratedVoiceTake] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PluginError.invalid("Voiceover text is required") }
        guard (1...8).contains(count) else { throw PluginError.invalid("Voice take count must be 1...8") }
        let resolved = try await resolveProvider(
            capability: "voice.synthesize", preferredProvider: preferredProvider)
        calling.insert("voice.synthesize")
        defer { calling.remove("voice.synthesize") }
        var generated: [GeneratedVoiceTake] = []
        do {
            while generated.count < count {
                let requested = count - generated.count
                let takes = try await requestVoiceTakes(
                    VoiceSynthesisRequest(
                        text: trimmed, language: language, requested: requested,
                        takeOffset: generated.count, outputRoot: outputRoot),
                    resolved: resolved)
                generated.append(contentsOf: takes.prefix(requested))
            }
            return generated
        } catch {
            discardVoiceTakes(generated)
            throw error
        }
    }

    func discardVoiceTakes(_ takes: [GeneratedVoiceTake], keeping keptURL: URL? = nil) {
        let kept = keptURL?.standardizedFileURL
        let keptDirectory = kept?.deletingLastPathComponent()
        for take in takes {
            let url = take.asset.url.standardizedFileURL
            if url != kept, url.deletingLastPathComponent() == keptDirectory {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let directories = Set(takes.map { $0.asset.url.deletingLastPathComponent().standardizedFileURL })
        for directory in directories where directory != keptDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func transcribe(
        mediaURL: URL, language: String, preferredProvider: String?, outputRoot: URL
    ) async throws -> GeneratedPluginCaptions {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Transcription source is unavailable")
        }
        let resolved = try await resolveProvider(
            capability: "captions.transcribe", preferredProvider: preferredProvider)
        let requestDirectory = try makeRequestDirectory(in: outputRoot)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: requestDirectory) } }
        calling.insert("captions.transcribe")
        defer { calling.remove("captions.transcribe") }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "captions.transcribe", provider: resolved.provider.id,
            params: .object([
                "language": .string(language), "mediaPath": .string(mediaURL.path),
                "outputDirectory": .string(requestDirectory.path),
            ]))
        guard let path = result.object["srtPath"]?.string, !path.isEmpty else {
            throw PluginError.invalid("Transcription plugin did not return srtPath")
        }
        let srt = try confinedOutput(path, in: requestDirectory, label: "Transcription plugin")
        let handle = try FileHandle(forReadingFrom: srt)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw PluginError.invalid("Transcription output must be UTF-8 SRT no larger than 4 MiB")
        }
        succeeded = true
        return GeneratedPluginCaptions(
            text: text, pluginID: resolved.plugin.id,
            pluginVersion: resolved.plugin.manifest.version, providerID: resolved.provider.id)
    }

    func detectBeats(
        mediaURL: URL, preferredProvider: String?
    ) async throws -> GeneratedBeatGrid {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Beat detection source is unavailable")
        }
        let resolved = try await resolveProvider(
            capability: "audio.beats", preferredProvider: preferredProvider)
        calling.insert("audio.beats")
        defer { calling.remove("audio.beats") }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "audio.beats", provider: resolved.provider.id,
            params: .object(["mediaPath": .string(mediaURL.path)]))
        let values = result.object["beatsSeconds"]?.array ?? []
        let beats = values.compactMap(\.double)
        guard let bpm = result.object["bpm"]?.double, bpm.isFinite, (20...400).contains(bpm),
            !beats.isEmpty, beats.count == values.count, beats.count <= 100_000,
            beats.allSatisfy({ $0.isFinite && $0 >= 0 }),
            zip(beats, beats.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw PluginError.invalid("Beat plugin returned invalid bpm or beatsSeconds") }
        return GeneratedBeatGrid(
            bpm: bpm, beatSeconds: beats, pluginID: resolved.plugin.id,
            pluginVersion: resolved.plugin.manifest.version, providerID: resolved.provider.id)
    }

    func analyzeLoudness(
        mediaURL: URL, preferredProvider: String?
    ) async throws -> GeneratedLoudnessMeasurement {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Loudness analysis source is unavailable")
        }
        let resolved = try await resolveProvider(
            capability: "audio.loudness", preferredProvider: preferredProvider)
        calling.insert("audio.loudness")
        defer { calling.remove("audio.loudness") }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "audio.loudness", provider: resolved.provider.id,
            params: .object(["mediaPath": .string(mediaURL.path)]))
        return GeneratedLoudnessMeasurement(
            measurement: try LoudnessMeasurement(result: result), pluginID: resolved.plugin.id,
            pluginVersion: resolved.plugin.manifest.version, providerID: resolved.provider.id)
    }

    private func resolveProvider(
        capability: String, preferredProvider: String?
    ) async throws -> ResolvedPluginProvider {
        let candidates = plugins.filter { plugin in
            (plugin.manifest.providers ?? []).contains { $0.capability == capability }
        }
        guard !candidates.isEmpty else {
            throw PluginError.invalid("Install a plugin that provides \(capability)")
        }
        let runner = healthRunner
        let checks = await withTaskGroup(
            of: (String, PluginHealth).self, returning: [(String, PluginHealth)].self
        ) { group in
            for plugin in candidates {
                group.addTask { (plugin.id, await runner.health(plugin: plugin)) }
            }
            var values: [(String, PluginHealth)] = []
            for await value in group { values.append(value) }
            return values
        }
        for (id, value) in checks { health[id] = value }
        let available = Set(
            candidates.filter { health[$0.id]?.state == .ready }
                .flatMap { $0.manifest.providers ?? [] }.map(\.id))
        guard let resolved = PluginProviderResolver.resolve(
            capability: capability, projectPreference: preferredProvider,
            userPreference: nil, plugins: candidates, availableProviderIDs: available)
        else { throw PluginError.invalid("No healthy provider is available for \(capability)") }
        return resolved
    }

    private func makeRequestDirectory(in outputRoot: URL) throws -> URL {
        let directory = outputRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func requestVoiceTakes(
        _ request: VoiceSynthesisRequest, resolved: ResolvedPluginProvider
    ) async throws -> [GeneratedVoiceTake] {
        let requestDirectory = try makeRequestDirectory(in: request.outputRoot)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: requestDirectory) } }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "voice.synthesize", provider: resolved.provider.id,
            params: .object([
                "language": .string(request.language), "outputDirectory": .string(requestDirectory.path),
                "takeCount": .integer(request.requested), "takeOffset": .integer(request.takeOffset),
                "text": .string(request.text),
            ]))
        let specifications = try VoiceSynthesisResultParser.parse(result)
        var takes: [GeneratedVoiceTake] = []
        for specification in specifications {
            let audio = try confinedOutput(
                specification.audioPath, in: requestDirectory, label: "Voice plugin")
            let asset = AVURLAsset(url: audio)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                try await !asset.loadTracks(withMediaType: .audio).isEmpty
            else { throw PluginError.invalid("Voice plugin output is not a valid audio file") }
            let providedScore = specification.score
            takes.append(
                GeneratedVoiceTake(
                    asset: GeneratedPluginAsset(
                        url: audio, pluginID: resolved.plugin.id,
                        pluginVersion: resolved.plugin.manifest.version,
                        providerID: resolved.provider.id),
                    durationSeconds: duration,
                    score: providedScore ?? Self.paceScore(text: request.text, duration: duration),
                    scoreSource: providedScore == nil ? "pace" : "provider"))
        }
        succeeded = true
        return takes
    }

    private static func paceScore(text: String, duration: Double) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let expected = max(1, Double(words) / 2.5)
        return max(0, min(1, 1 - abs(duration - expected) / expected))
    }

    private func confinedOutput(_ path: String, in directory: URL, label: String) throws -> URL {
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(resolvedDirectory.path + "/"),
            FileManager.default.fileExists(atPath: resolved.path)
        else { throw PluginError.invalid("\(label) returned output outside its request directory") }
        return resolved
    }

    func choosePlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a BashCut plugin folder containing plugin.json")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let result = PluginCatalog.discover(in: [directory.deletingLastPathComponent()])
        guard let plugin = result.plugins.first(where: { $0.directory.standardizedFileURL == directory.standardizedFileURL })
        else {
            message = result.diagnostics.first ?? String(localized: "This folder is not a valid BashCut plugin.")
            return
        }
        pendingInstall = PendingPluginInstall(plugin: plugin)
    }

    func installPendingPlugin() {
        guard let pendingInstall else { return }
        let source = pendingInstall.plugin.directory
        let manifest = pendingInstall.plugin.manifest
        let installRoot = userRoot
        let destination = installRoot.appendingPathComponent(manifest.id, isDirectory: true)
        installing = true
        self.pendingInstall = nil
        Task {
            defer { installing = false }
            do {
                try await Task.detached {
                    let manager = FileManager.default
                    try manager.createDirectory(at: installRoot, withIntermediateDirectories: true)
                    guard !manager.fileExists(atPath: destination.path) else {
                        throw PluginError.invalid("Plugin \(manifest.id) is already installed")
                    }
                    let stagingRoot = installRoot.appendingPathComponent(".staging-\(UUID().uuidString)")
                    let staged = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
                    try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                    defer { try? manager.removeItem(at: stagingRoot) }
                    try manager.copyItem(at: source, to: staged)
                    let stagedPlugin = InstalledPlugin(manifest: manifest, directory: staged)
                    _ = try stagedPlugin.entrypointURL()
                    for dependency in manifest.dependencies {
                        guard let recipe = dependency.install else { continue }
                        try Self.run(recipe.command, directory: staged)
                    }
                    try manager.moveItem(at: staged, to: destination)
                }.value
                message = String(localized: "Plugin installed")
                refresh(projectRoot: projectRoot)
            } catch { message = error.localizedDescription }
        }
    }

    private nonisolated static func run(_ command: PluginCommand, directory: URL) throws {
        let process = Process()
        let executable = command.executable.contains("/")
            ? directory.appendingPathComponent(command.executable).path : "/usr/bin/env"
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = command.executable.contains("/")
            ? command.arguments : [command.executable] + command.arguments
        process.currentDirectoryURL = directory
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: logURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: logURL)
        }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try output.synchronize()
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            let detail = String(bytes: data.suffix(4_000), encoding: .utf8) ?? ""
            throw PluginError.invalid("Dependency install failed: \(detail)")
        }
    }
}
