import BashCutPlugin
import BashCutProject
import Foundation

/// Catalog roots in resolution order: project overrides user, which overrides bundled plugins.
/// The App Store channel searches the bundled root only (`PluginChannel`).
public struct PluginRoots: Sendable, Equatable {
    public let user: URL
    public let bundled: URL?
    /// Project and user plugins are found (false in the App Store build).
    public let includesUserPlugins: Bool
    /// The saved copy of the plugin registry; next to `user` unless given (tests keep everything in one folder).
    public let registryCache: URL

    public init(user: URL, bundled: URL?, includesUserPlugins: Bool = true, registryCache: URL? = nil) {
        self.user = user
        self.bundled = bundled
        self.includesUserPlugins = includesUserPlugins
        self.registryCache = registryCache ?? legacyRegistryCacheFor(user)
    }

    /// Where the registry cache was before #101: `Registry/` next to the user plugins folder.
    public var legacyRegistryCache: URL { legacyRegistryCacheFor(user) }

    public static var standard: PluginRoots {
        PluginRoots(
            user: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BashCut/Plugins", isDirectory: true),
            bundled: PluginFolders.bundled, includesUserPlugins: PluginChannel.current.allowsUserPlugins,
            registryCache: PluginFolders.registryCache)
    }

    public func ordered(projectRoot: URL?) -> [URL] {
        var roots: [URL] = []
        if includesUserPlugins {
            if let projectRoot { roots.append(projectRoot.appendingPathComponent(".bashcut/plugins")) }
            roots.append(user)
        }
        if let bundled { roots.append(bundled) }
        return roots
    }
}

private func legacyRegistryCacheFor(_ user: URL) -> URL {
    user.deletingLastPathComponent().appendingPathComponent("Registry", isDirectory: true)
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
    /// The plugin's option values (project over user over defaults), sent as `options` with every capability
    /// request so providers honour settings such as the chosen voice.
    public var optionValues: (@Sendable (InstalledPlugin) async -> [String: JSONValue])?
    /// Creates each plugin's data and cache folders (`PluginFolders`) before calling it. Off in tests.
    public var preparesPluginFolders = false
    /// Manifests already read, so a catalog refresh reads only plugins that changed (#103).
    let catalogCache = PluginCatalogCache()

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
        PluginCatalog.discover(in: roots.ordered(projectRoot: projectRoot), bundled: roots.bundled, cache: catalogCache)
    }

    /// Whether the plugin may run now: approved, unchanged, turned on and API-compatible. Checks every file in
    /// the plugin's folder; call it right before running the plugin, off the main actor when listing many.
    public func availability(_ plugin: InstalledPlugin) -> PluginAvailability {
        if let trust { return trust.availability(of: plugin) }
        return plugin.manifest.incompatibility.map(PluginAvailability.outdated) ?? .ready
    }

    /// `availability` from the last file check, or nil when the files have to be checked again
    /// (`PluginTrustStore.knownAvailability`).
    public func knownAvailability(_ plugin: InstalledPlugin) -> PluginAvailability? {
        if let trust { return trust.knownAvailability(of: plugin) }
        return availability(plugin)
    }

    /// Plugins in the catalog that may run now.
    public func runnablePlugins(projectRoot: URL?) -> [InstalledPlugin] {
        catalog(projectRoot: projectRoot).plugins.filter { availability($0) == .ready }
    }

    public func health(_ plugin: InstalledPlugin) async -> PluginHealth {
        let state = availability(plugin)
        guard state == .ready else { return .notChecked(plugin, reason: state.detail) }
        return await healthTransport.health(plugin: plugin)
    }

    // MARK: Capabilities

    /// Asks one provider for voice takes until `count` exist; a failure discards the takes made so far.
    public func synthesizeVoiceTakes(
        text: String, language: String, count: Int = 3, preferredProvider: String?,
        projectRoot: URL, outputRoot: URL, cloneConsent: Bool = false
    ) async throws -> [GeneratedVoiceTake] {
        let first = VoiceSynthesisCapability(
            text: text, language: language, takeCount: count, outputRoot: outputRoot, cloneConsent: cloneConsent)
        try first.validate()
        let resolved = try await resolve(
            VoiceSynthesisCapability.capability, preferredProvider: preferredProvider, projectRoot: projectRoot)
        var generated: [GeneratedVoiceTake] = []
        do {
            while generated.count < count {
                let requested = count - generated.count
                let batch = VoiceSynthesisCapability(
                    text: text, language: language, takeCount: requested, takeOffset: generated.count,
                    outputRoot: outputRoot, cloneConsent: cloneConsent)
                generated.append(contentsOf: try await run(batch, using: resolved).prefix(requested))
            }
            return generated
        } catch {
            Self.discardVoiceTakes(generated)
            throw error
        }
    }

    public func transcribe(
        mediaURL: URL, language: String, range: ClosedRange<Double>? = nil, preferredProvider: String?, projectRoot: URL,
        outputRoot: URL
    ) async throws -> GeneratedPluginCaptions {
        try await run(
            TranscriptionCapability(mediaURL: mediaURL, language: language, outputRoot: outputRoot, range: range),
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
        try await analyzeLoudness(mediaURL: mediaURL, bands: false, preferredProvider: preferredProvider, projectRoot: projectRoot)
    }

    public func analyzeLoudness(
        mediaURL: URL, bands: Bool, curve: Bool = false, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedLoudnessMeasurement {
        try await run(
            LoudnessCapability(mediaURL: mediaURL, bands: bands, curve: curve), preferredProvider: preferredProvider,
            projectRoot: projectRoot)
    }

    public func alignText(
        mediaURL: URL, text: String, language: String, preferredProvider: String?, projectRoot: URL?
    ) async throws -> [CaptionWords.Timed] {
        try await run(
            CaptionsAlignCapability(mediaURL: mediaURL, text: text, language: language),
            preferredProvider: preferredProvider, projectRoot: projectRoot)
    }

    public func analyzeEnergy(
        mediaURL: URL, count: Int?, windowSeconds: Double?, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedEnergy {
        try await run(
            EnergyCapability(mediaURL: mediaURL, count: count, windowSeconds: windowSeconds),
            preferredProvider: preferredProvider, projectRoot: projectRoot)
    }

    public func syncAudio(
        mediaURL: URL, otherURL: URL, preferredProvider: String?, projectRoot: URL?
    ) async throws -> GeneratedAudioSync {
        try await run(
            AudioSyncCapability(mediaURL: mediaURL, otherURL: otherURL), preferredProvider: preferredProvider,
            projectRoot: projectRoot)
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
    /// With `kind` (library providers, API 6), only providers that serve that library kind count.
    public func resolve(
        _ capability: String, preferredProvider: String?, projectRoot: URL?, kind: LibraryKind? = nil
    ) async throws -> ResolvedPluginProvider {
        func matches(_ provider: PluginProvider) -> Bool {
            provider.capability == capability && (kind.map(provider.serves) ?? true)
        }
        let declaring = catalog(projectRoot: projectRoot).plugins.filter { plugin in
            (plugin.manifest.providers ?? []).contains(where: matches)
        }
        guard !declaring.isEmpty else {
            throw PluginError.invalid(
                "Install a plugin that provides \(capability)" + (kind.map { " for \($0.rawValue) items" } ?? ""))
        }
        let all = catalog(projectRoot: projectRoot).plugins
        let problems = declaring.contains { !$0.manifest.requirements.isEmpty }
            ? PluginRequirements.problems(all) { (knownAvailability($0) ?? availability($0)) == .ready } : [:]
        let candidates = declaring.filter { availability($0) == .ready && problems[$0.id] == nil }
        guard !candidates.isEmpty else {
            let reasons = declaring.map { "\($0.manifest.displayName): \(problems[$0.id] ?? availability($0).detail)" }
            throw PluginError.invalid("No enabled provider for \(capability). " + reasons.joined(separator: "; "))
        }
        let ready = await withTaskGroup(of: InstalledPlugin?.self, returning: [InstalledPlugin].self) { group in
            for plugin in candidates {
                group.addTask { await health(plugin).state == .ready ? plugin : nil }
            }
            var values: [InstalledPlugin] = []
            for await value in group { if let value { values.append(value) } }
            return values
        }
        let available = Set(ready.flatMap { $0.manifest.providers ?? [] }.filter(matches).map(\.id))
        guard let resolved = PluginProviderResolver.resolve(
            capability: capability, projectPreference: preferredProvider,
            userPreference: nil, plugins: candidates, availableProviderIDs: available)
        else { throw PluginError.invalid("No healthy provider is available for \(capability)") }
        return resolved
    }
}
