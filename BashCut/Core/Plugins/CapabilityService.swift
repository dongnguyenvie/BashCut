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

/// The one path from a capability request to a validated, provenance-tagged result. Native panels,
/// automation commands and export all call this service; none of them talk to plugin processes directly.
/// Each capability is a `CapabilityAdapter`; the methods below are shortcuts for the built-in ones.
public struct CapabilityService: Sendable {
    public let roots: PluginRoots
    let transport: any PluginTransport
    private let healthTransport: any PluginTransport
    /// The user's approvals and on/off switches. Without one (tests), every discovered plugin may run.
    public let trust: PluginTrustStore?

    public init(
        roots: PluginRoots = .standard, transport: any PluginTransport = PluginRouter(),
        healthTransport: any PluginTransport = PluginProcessRunner(timeout: 15, maximumOutputBytes: 256 * 1024),
        trust: PluginTrustStore? = nil
    ) {
        self.roots = roots
        self.transport = transport
        self.healthTransport = healthTransport
        self.trust = trust
    }

    public func catalog(projectRoot: URL?) -> PluginCatalogResult {
        PluginCatalog.discover(in: roots.ordered(projectRoot: projectRoot))
    }

    /// Whether the plugin may run now: approved, unchanged, turned on and API-compatible.
    public func availability(_ plugin: InstalledPlugin) -> PluginAvailability {
        if let trust { return trust.availability(of: plugin) }
        return plugin.manifest.incompatibility.map(PluginAvailability.outdated) ?? .ready
    }

    /// Plugins in the catalog that may run now.
    public func runnablePlugins(projectRoot: URL?) -> [InstalledPlugin] {
        catalog(projectRoot: projectRoot).plugins.filter { availability($0) == .ready }
    }

    public func health(_ plugin: InstalledPlugin) async -> PluginHealth {
        await healthTransport.health(plugin: plugin)
    }

    // MARK: Capabilities

    /// Asks one provider for voice takes until `count` exist; a failure discards the takes made so far.
    public func synthesizeVoiceTakes(
        text: String, language: String, count: Int = 3, preferredProvider: String?,
        projectRoot: URL, outputRoot: URL
    ) async throws -> [GeneratedVoiceTake] {
        let first = VoiceSynthesisCapability(text: text, language: language, takeCount: count, outputRoot: outputRoot)
        try first.validate()
        let resolved = try await resolve(
            VoiceSynthesisCapability.capability, preferredProvider: preferredProvider, projectRoot: projectRoot)
        var generated: [GeneratedVoiceTake] = []
        do {
            while generated.count < count {
                let requested = count - generated.count
                let batch = VoiceSynthesisCapability(
                    text: text, language: language, takeCount: requested, takeOffset: generated.count,
                    outputRoot: outputRoot)
                generated.append(contentsOf: try await run(batch, using: resolved).prefix(requested))
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
        try await run(
            TranscriptionCapability(mediaURL: mediaURL, language: language, outputRoot: outputRoot),
            preferredProvider: preferredProvider, projectRoot: projectRoot)
    }

    public func detectBeats(
        mediaURL: URL, preferredProvider: String?, projectRoot: URL
    ) async throws -> GeneratedBeatGrid {
        try await run(BeatDetectionCapability(mediaURL: mediaURL), preferredProvider: preferredProvider, projectRoot: projectRoot)
    }

    public func analyzeLoudness(
        mediaURL: URL, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedLoudnessMeasurement {
        try await run(LoudnessCapability(mediaURL: mediaURL), preferredProvider: preferredProvider, projectRoot: projectRoot)
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

    // MARK: Resolution

    /// Probes every candidate's dependencies, then applies the project preference or the highest priority.
    public func resolve(
        _ capability: String, preferredProvider: String?, projectRoot: URL?
    ) async throws -> ResolvedPluginProvider {
        let declaring = catalog(projectRoot: projectRoot).plugins.filter { plugin in
            (plugin.manifest.providers ?? []).contains { $0.capability == capability }
        }
        guard !declaring.isEmpty else {
            throw PluginError.invalid("Install a plugin that provides \(capability)")
        }
        let candidates = declaring.filter { availability($0) == .ready }
        guard !candidates.isEmpty else {
            let reasons = declaring.map { "\($0.manifest.name): \(availability($0).detail)" }
            throw PluginError.invalid("No enabled provider for \(capability). " + reasons.joined(separator: "; "))
        }
        let transport = healthTransport
        let ready = await withTaskGroup(of: InstalledPlugin?.self, returning: [InstalledPlugin].self) { group in
            for plugin in candidates {
                group.addTask { await transport.health(plugin: plugin).state == .ready ? plugin : nil }
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
}
