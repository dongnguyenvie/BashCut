import AVFoundation
import BashCutPlugin
import BashCutProject
import Foundation

/// Catalog roots in resolution order: project overrides user, which overrides bundled plugins.
public struct PluginRoots: Sendable, Equatable {
    public let user: URL
    public let bundled: URL?

    public init(user: URL, bundled: URL?) {
        self.user = user
        self.bundled = bundled
    }

    public static var standard: PluginRoots {
        PluginRoots(
            user: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BashCut/Plugins", isDirectory: true),
            bundled: Bundle.main.builtInPlugInsURL)
    }

    public func ordered(projectRoot: URL?) -> [URL] {
        var roots: [URL] = []
        if let projectRoot { roots.append(projectRoot.appendingPathComponent(".bashcut/plugins")) }
        roots.append(user)
        if let bundled { roots.append(bundled) }
        return roots
    }
}

private struct VoiceTakeRequest {
    let text: String
    let language: String
    let requested: Int
    let takeOffset: Int
    let outputRoot: URL
}

/// The one path from a capability request to a validated, provenance-tagged result. Native panels,
/// automation commands and export all call this service; none of them talk to plugin processes directly.
public struct CapabilityService: Sendable {
    public let roots: PluginRoots
    private let runner: PluginProcessRunner
    private let healthRunner: PluginProcessRunner

    public init(
        roots: PluginRoots = .standard, runner: PluginProcessRunner = PluginProcessRunner(),
        healthRunner: PluginProcessRunner = PluginProcessRunner(timeout: 15, maximumOutputBytes: 256 * 1024)
    ) {
        self.roots = roots
        self.runner = runner
        self.healthRunner = healthRunner
    }

    public func catalog(projectRoot: URL?) -> PluginCatalogResult {
        PluginCatalog.discover(in: roots.ordered(projectRoot: projectRoot))
    }

    public func health(_ plugin: InstalledPlugin) async -> PluginHealth {
        await healthRunner.health(plugin: plugin)
    }

    // MARK: Capabilities

    public func synthesizeVoiceTakes(
        text: String, language: String, count: Int = 3, preferredProvider: String?,
        projectRoot: URL, outputRoot: URL
    ) async throws -> [GeneratedVoiceTake] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PluginError.invalid("Voiceover text is required") }
        guard (1...8).contains(count) else { throw PluginError.invalid("Voice take count must be 1...8") }
        let resolved = try await resolve(
            "voice.synthesize", preferredProvider: preferredProvider, projectRoot: projectRoot)
        var generated: [GeneratedVoiceTake] = []
        do {
            while generated.count < count {
                let requested = count - generated.count
                let takes = try await requestVoiceTakes(
                    VoiceTakeRequest(
                        text: trimmed, language: language, requested: requested,
                        takeOffset: generated.count, outputRoot: outputRoot),
                    resolved: resolved)
                generated.append(contentsOf: takes.prefix(requested))
            }
            return generated
        } catch {
            Self.discardVoiceTakes(generated)
            throw error
        }
    }

    public func transcribe(
        mediaURL: URL, language: String, preferredProvider: String?, projectRoot: URL, outputRoot: URL
    ) async throws -> GeneratedPluginCaptions {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Transcription source is unavailable")
        }
        let resolved = try await resolve(
            "captions.transcribe", preferredProvider: preferredProvider, projectRoot: projectRoot)
        let requestDirectory = try Self.makeRequestDirectory(in: outputRoot)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: requestDirectory) } }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "captions.transcribe", provider: resolved.provider.id,
            params: .object([
                "language": .string(language), "mediaPath": .string(mediaURL.path),
                "outputDirectory": .string(requestDirectory.path),
            ]))
        guard let path = result.object["srtPath"]?.string, !path.isEmpty else {
            throw PluginError.invalid("Transcription plugin did not return srtPath")
        }
        let srt = try Self.confinedOutput(path, in: requestDirectory, label: "Transcription plugin")
        let handle = try FileHandle(forReadingFrom: srt)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: SubRip.maximumBytes + 1) ?? Data()
        guard data.count <= SubRip.maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw PluginError.invalid("Transcription output must be UTF-8 SRT no larger than 4 MiB")
        }
        succeeded = true
        return GeneratedPluginCaptions(text: text, provenance: PluginProvenance(resolved))
    }

    public func detectBeats(
        mediaURL: URL, preferredProvider: String?, projectRoot: URL
    ) async throws -> GeneratedBeatGrid {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Beat detection source is unavailable")
        }
        let resolved = try await resolve(
            "audio.beats", preferredProvider: preferredProvider, projectRoot: projectRoot)
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
        return GeneratedBeatGrid(bpm: bpm, beatSeconds: beats, provenance: PluginProvenance(resolved))
    }

    public func analyzeLoudness(
        mediaURL: URL, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedLoudnessMeasurement {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Loudness analysis source is unavailable")
        }
        let resolved = try await resolve(
            "audio.loudness", preferredProvider: preferredProvider, projectRoot: projectRoot)
        let result = try await runner.call(
            plugin: resolved.plugin, method: "audio.loudness", provider: resolved.provider.id,
            params: .object(["mediaPath": .string(mediaURL.path)]))
        return GeneratedLoudnessMeasurement(
            measurement: try LoudnessMeasurement(result: result), provenance: PluginProvenance(resolved))
    }

    /// Removes discarded takes and their request folders, keeping only `keptURL` when given.
    public static func discardVoiceTakes(_ takes: [GeneratedVoiceTake], keeping keptURL: URL? = nil) {
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

    // MARK: Resolution and validation

    /// Probes every candidate's dependencies, then applies the project preference or the highest priority.
    public func resolve(
        _ capability: String, preferredProvider: String?, projectRoot: URL?
    ) async throws -> ResolvedPluginProvider {
        let candidates = catalog(projectRoot: projectRoot).plugins.filter { plugin in
            (plugin.manifest.providers ?? []).contains { $0.capability == capability }
        }
        guard !candidates.isEmpty else {
            throw PluginError.invalid("Install a plugin that provides \(capability)")
        }
        let runner = healthRunner
        let ready = await withTaskGroup(of: InstalledPlugin?.self, returning: [InstalledPlugin].self) { group in
            for plugin in candidates {
                group.addTask { await runner.health(plugin: plugin).state == .ready ? plugin : nil }
            }
            var values: [InstalledPlugin] = []
            for await value in group { if let value { values.append(value) } }
            return values
        }
        let available = Set(ready.flatMap { $0.manifest.providers ?? [] }.map(\.id))
        guard let resolved = PluginProviderResolver.resolve(
            capability: capability, projectPreference: preferredProvider,
            userPreference: nil, plugins: candidates, availableProviderIDs: available)
        else { throw PluginError.invalid("No healthy provider is available for \(capability)") }
        return resolved
    }

    private func requestVoiceTakes(
        _ request: VoiceTakeRequest, resolved: ResolvedPluginProvider
    ) async throws -> [GeneratedVoiceTake] {
        let requestDirectory = try Self.makeRequestDirectory(in: request.outputRoot)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: requestDirectory) } }
        let result = try await runner.call(
            plugin: resolved.plugin, method: "voice.synthesize", provider: resolved.provider.id,
            params: .object([
                "language": .string(request.language), "outputDirectory": .string(requestDirectory.path),
                "takeCount": .integer(request.requested), "takeOffset": .integer(request.takeOffset),
                "text": .string(request.text),
            ]))
        var takes: [GeneratedVoiceTake] = []
        for specification in try VoiceSynthesisResultParser.parse(result) {
            let audio = try Self.confinedOutput(
                specification.audioPath, in: requestDirectory, label: "Voice plugin")
            let asset = AVURLAsset(url: audio)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                try await !asset.loadTracks(withMediaType: .audio).isEmpty
            else { throw PluginError.invalid("Voice plugin output is not a valid audio file") }
            takes.append(
                GeneratedVoiceTake(
                    asset: GeneratedPluginAsset(url: audio, provenance: PluginProvenance(resolved)),
                    durationSeconds: duration,
                    score: specification.score ?? Self.paceScore(text: request.text, duration: duration),
                    scoreSource: specification.score == nil ? "pace" : "provider"))
        }
        succeeded = true
        return takes
    }

    static func paceScore(text: String, duration: Double) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let expected = max(1, Double(words) / 2.5)
        return max(0, min(1, 1 - abs(duration - expected) / expected))
    }

    private static func makeRequestDirectory(in outputRoot: URL) throws -> URL {
        let directory = outputRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private static func confinedOutput(_ path: String, in directory: URL, label: String) throws -> URL {
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(resolvedDirectory.path + "/"),
            FileManager.default.fileExists(atPath: resolved.path)
        else { throw PluginError.invalid("\(label) returned output outside its request directory") }
        return resolved
    }
}
