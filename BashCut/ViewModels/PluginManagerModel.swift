import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation
import Observation

struct PendingPluginInstall: Identifiable {
    let id = UUID()
    let plugin: InstalledPlugin
    /// Set when the plugin came from the registry: the verified download, removed after install or cancel.
    var archive: StagedPluginArchive?
    /// Set when the plugin came from a folder, zip or plugin.json on this Mac ("Add Plugin…"): the checked copy,
    /// removed after install or cancel.
    var local: StagedLocalPlugin?
    /// Where it goes: the user folder, or the open project for a plugin from this Mac or a link. Chosen in the
    /// approval (`PluginManagerModel.installScope`) and fixed when the user approves.
    var scope: PluginInstallScope = .user
    /// Link (developer mode): install a link to the developer's folder instead of a copy. Chosen in the approval
    /// (`PluginManagerModel.installMode`) like the scope.
    var mode: PluginInstallMode = .copy
    /// Re-runs the dependency recipes of an installed plugin (Install dependencies…) instead of installing it.
    var repair = false
    /// Dependency probes run on the unpacked plugin before the approval, so the sheet can say what this Mac has,
    /// what setup will install, and what cannot work at all.
    var preflight: PluginHealth?
    /// Replaces an installed copy (an update).
    var replacing = false
}

/// Tabs of the Plugins sheet.
enum PluginSheetTab: String, CaseIterable, Identifiable {
    case installed, browse, updates, activity
    var id: String { rawValue }
    /// The App Store build has no registry, so no Browse or Updates.
    static var visible: [PluginSheetTab] {
        PluginChannel.current.allowsUserPlugins ? allCases : [.installed, .activity]
    }
    var title: String {
        switch self {
        case .installed: String(localized: "Installed")
        case .browse: String(localized: "Browse")
        case .updates: String(localized: "Updates")
        case .activity: String(localized: "Hook Activity")
        }
    }
}

struct PluginProviderChoice: Identifiable, Equatable {
    let pluginID: String
    let pluginName: String
    let provider: PluginProvider
    var id: String { provider.id }
}

/// An action a plugin adds, with its parsed `when` condition and shortcut.
struct ContributedAction: Identifiable {
    let plugin: InstalledPlugin
    let spec: PluginActionContribution
    let when: PluginWhen?
    /// nil when the plugin gave none or it collides with a built-in or earlier plugin shortcut.
    let shortcut: UIShortcut?
    var id: String { spec.id }
    var title: String { spec.title.text }
    var params: [PluginOption] { spec.params ?? [] }
}

/// One delivered hook, for the Plugins sheet and `plugins hooks`.
struct PluginHookRun: Identifiable {
    enum Outcome: String { case delivered, applied, proposed, ignored, failed, dropped }
    let id = UUID()
    let date: Date
    let pluginID: String
    let event: String
    let outcome: Outcome
    let detail: String

    var json: JSONValue {
        .object([
            "date": .string(ISO8601DateFormatter().string(from: date)), "plugin": .string(pluginID),
            "event": .string(event), "outcome": .string(outcome.rawValue), "detail": .string(detail),
        ])
    }
}

/// An edit a hook proposed, waiting for the user (or an agent) to apply or discard it.
struct PluginProposal: Identifiable {
    let id: String
    let plugin: InstalledPlugin
    let event: String
    let proposal: PluginEditProposal
    let createdAt: Date
    var title: String { proposal.label ?? "\(plugin.manifest.displayName): \(event)" }

    var json: JSONValue {
        .object([
            "id": .string(id), "plugin": .string(plugin.id), "event": .string(event), "label": .string(title),
            "message": proposal.message.map(JSONValue.string) ?? .null,
            "operations": .array(proposal.operations.map(\.json)),
            "baseRev": proposal.baseRevision.map(JSONValue.integer) ?? .null,
            "pluginData": proposal.pluginData ?? .null,
        ])
    }
}

enum PluginText {
    /// The language plugin titles are shown in: the app's interface language.
    static var language: String { LocalizedText.preferredLanguage }
}

/// UI state for the plugin catalog. Capability calls go through `CapabilityService`, which the
/// document and automation commands share; this model tracks the catalog, the user's trust and on/off
/// decisions, the actions plugins contribute, hook activity and which capabilities are running.
@MainActor @Observable final class PluginManagerModel {
    var plugins: [InstalledPlugin] = []
    var diagnostics: [String] = []
    var pendingInstall: PendingPluginInstall?
    var installing = false
    var message = ""
    var health: [String: PluginHealth] = [:]
    var checking: Set<String> = []
    var calling: Set<String> = []
    /// Why each plugin may or may not run, as last checked. Running a plugin checks its files again.
    var availability: [String: PluginAvailability] = [:]
    /// Plugins whose files are being checked off the main actor (#103). Until the check ends they keep their last
    /// known availability, or count as not approved when there is none, so their actions and hooks wait.
    var checkingFiles: Set<String> = []
    @ObservationIgnored var fileCheckQueue: [InstalledPlugin] = []
    @ObservationIgnored var fileCheckBatch: Set<String> = []
    @ObservationIgnored private var catalogDiagnostics: [String] = []
    /// Actions of runnable plugins, in catalog order.
    var actions: [ContributedAction] = []
    /// The library packs ready plugins ship (`contributes.library`, API 6; `rebuildLibrary`).
    var library = PluginLibraryState()
    /// The agent skills ready plugins ship (`contributes.skills`, API 7; `rebuildSkills`).
    var skills: [PluginSkill] = []
    /// Skills that could not be read, also in `diagnostics`.
    var skillProblems: [String] = []
    /// Called when `skills` changes, so the document links them for agents and lists them in their knowledge.
    @ObservationIgnored var onSkillsChanged: (@MainActor () -> Void)?
    /// When each action last started, so MCP lists recently used actions first (#98).
    @ObservationIgnored var lastRun: [String: Date] = [:]
    /// Most recent hook deliveries, newest last.
    var hookLog: [PluginHookRun] = []
    var proposals: [PluginProposal] = []
    /// The action whose parameter sheet is open.
    var pendingAction: PendingPluginAction?
    /// Actions waiting for the user to confirm them, oldest first; the sheet shows the first.
    var confirmations: [PendingPluginConfirm] = []
    var tab: PluginSheetTab = .installed
    /// Install or setup in progress: fraction from `::progress` lines, the current step and recent output.
    var installProgress: Double?
    var installStep = ""
    var installLog: [String] = []
    var installJob: String?
    /// The document's job center, so installs show in `jobs status` and can be cancelled.
    @ObservationIgnored weak var jobs: JobCenter?
    /// The remote catalog, once fetched (or the cached copy).
    var registry: PluginRegistryDocument?
    var registryFetchedAt: Date?
    /// Why the last refresh failed; the cached copy, if any, is still shown.
    var registryError: String?
    var loadingRegistry = false
    /// Plugins being downloaded and verified.
    var downloading: Set<String> = []
    /// Narrows Browse to providers of one capability (a panel's "Find a plugin…").
    var browseCapability: String?
    /// The Add Plugin… sheet (paste a link, or choose a file or folder).
    var showAddPlugin = false
    /// A plugin link is downloading.
    var addingLink = false
    /// Where the pending plugin from this Mac or a link goes. Kept apart from `pendingInstall` so changing it does not
    /// re-present the approval sheet.
    var installScope: PluginInstallScope = .user
    /// Copy or Link (developer mode) for the pending plugin folder, kept apart from `pendingInstall` like the scope.
    var installMode: PluginInstallMode = .copy
    /// Narrows Browse to one category (the chips above the list, `ui view --plugins-category`).
    var browseCategory: PluginCategory?
    @ObservationIgnored private var cachedRegistryClient: PluginRegistryClient?
    /// The client for the current `pluginRegistryURL`; a changed URL takes effect without restarting.
    var registryClient: PluginRegistryClient {
        let url = Self.registryURL
        if let client = cachedRegistryClient, client.url == url { return client }
        let roots = service.roots
        PluginRegistryClient.migrateCache(from: roots.legacyRegistryCache, to: roots.registryCache)
        let client = PluginRegistryClient(url: url, cacheDirectory: roots.registryCache)
        cachedRegistryClient = client
        registry = nil
        return client
    }
    @ObservationIgnored let trust: PluginTrustStore
    /// Values of `secret` options (Keychain; in memory in tests).
    @ObservationIgnored var secrets = PluginSecretStore()
    @ObservationIgnored var service: CapabilityService
    private var projectRoot: URL?
    var currentProjectRoot: URL? { projectRoot }
    static let hookLogLimit = 200

    init(trust: PluginTrustStore = .standard) {
        self.trust = trust
        service = CapabilityService(trust: trust)
        service.preparesPluginFolders = true
        #if DEBUG
            // scripts/dev-link.sh plugins can change while they are written; release builds pin every file.
            trust.relaxesLinkedPlugins = true
        #endif
    }

    private var userRoot: URL { service.roots.user }

    /// Reads the catalog and what is already known about each plugin, without walking plugin folders, so it is
    /// cheap enough to call whenever a panel appears (#103). Plugins not checked yet in this session, or whose
    /// plugin.json or entrypoint changed, are checked in the background; `checkFiles` checks every plugin again.
    func refresh(projectRoot: URL?, checkFiles: Bool = false) {
        self.projectRoot = projectRoot
        let result = service.catalog(projectRoot: projectRoot)
        plugins = result.plugins
        catalogDiagnostics = result.diagnostics
        let ids = Set(plugins.map(\.id))
        health = health.filter { ids.contains($0.key) }
        let unchecked = applyKnownAvailability(checkFiles: checkFiles)
        rebuildActions()
        if !unchecked.isEmpty || !fileCheckQueue.isEmpty { queueFileChecks(unchecked) }
    }

    func rebuildActions() {
        diagnostics = catalogDiagnostics
        var taken = Set(UIAction.allCases.flatMap(\.shortcuts))
        var list: [ContributedAction] = []
        for plugin in plugins where availability[plugin.id] == .ready {
            for spec in plugin.manifest.actions {
                var shortcut = spec.shortcut.flatMap(UIShortcut.init(parsing:))
                if let candidate = shortcut {
                    if taken.contains(candidate) {
                        diagnostics.append("\(spec.id): shortcut \(candidate) is already used")
                        shortcut = nil
                    } else {
                        taken.insert(candidate)
                    }
                }
                list.append(ContributedAction(
                    plugin: plugin, spec: spec, when: spec.when.flatMap { try? PluginWhen(parsing: $0) },
                    shortcut: shortcut))
            }
        }
        actions = list
        rebuildLibrary()
        rebuildSkills()
    }

    func action(_ id: String) -> ContributedAction? { actions.first { $0.id == id } }

    func actions(at placement: String) -> [ContributedAction] {
        actions.filter { $0.spec.placements.contains(placement) }
    }

    /// Plugins whose hooks receive `event` now.
    func subscribers(for event: PluginEvent) -> [(InstalledPlugin, PluginHookContribution)] {
        plugins.compactMap { plugin in
            guard availability[plugin.id] == .ready, trust.hooksEnabled(plugin),
                let hook = plugin.manifest.hooks.first(where: { $0.event == event.rawValue })
            else { return nil }
            return (plugin, hook)
        }
    }

    func plugin(_ id: String) -> InstalledPlugin? { plugins.first { $0.id == id } }

    // MARK: User decisions

    /// Pins the plugin's current files so it may run. Only the Plugins sheet calls this; no command does.
    func trustPlugin(_ plugin: InstalledPlugin) {
        do {
            try trust.trust(plugin)
            message = String(format: String(localized: "Trusted %@"), plugin.manifest.displayName)
        } catch { message = error.localizedDescription }
        refresh(projectRoot: projectRoot)
    }

    func revokeTrust(_ plugin: InstalledPlugin) {
        do { try trust.revoke(plugin) } catch { message = error.localizedDescription }
        stopSession(plugin.id)
        refresh(projectRoot: projectRoot)
    }

    func setEnabled(_ plugin: InstalledPlugin, enabled: Bool? = nil, hooks: Bool? = nil) throws {
        try trust.setEnabled(plugin, enabled: enabled, hooks: hooks)
        if enabled == false { stopSession(plugin.id) }
        refresh(projectRoot: projectRoot)
    }

    func isEnabled(_ plugin: InstalledPlugin) -> Bool { trust.grant(for: plugin)?.enabled ?? true }

    func stopSession(_ pluginID: String) {
        Task { await PluginSessionTransport.shared.stop(pluginID: pluginID) }
    }

    // MARK: Hook log

    func log(_ plugin: String, _ event: String, _ outcome: PluginHookRun.Outcome, _ detail: String = "") {
        hookLog.append(PluginHookRun(date: Date(), pluginID: plugin, event: event, outcome: outcome, detail: detail))
        if hookLog.count > Self.hookLogLimit { hookLog.removeFirst(hookLog.count - Self.hookLogLimit) }
        DebugLog.write("plugin", "hook \(event) → \(plugin): \(outcome.rawValue) \(detail)")
    }

    func checkHealth(_ plugin: InstalledPlugin) {
        guard !checking.contains(plugin.id) else { return }
        Task { await checkHealthNow(plugin) }
    }

    /// Runs the plugin's health command and records the result.
    @discardableResult
    func checkHealthNow(_ plugin: InstalledPlugin) async -> PluginHealth {
        checking.insert(plugin.id)
        defer { checking.remove(plugin.id) }
        let result = await service.health(plugin)
        health[plugin.id] = result
        return result
    }

    /// Marks a capability busy for the UI while `body` runs. A capability runs one request at a time.
    func running<T>(_ capability: String, _ body: () async throws -> T) async throws -> T {
        guard calling.insert(capability).inserted else {
            throw PluginError.invalid("\(capability) is already running")
        }
        defer { calling.remove(capability) }
        return try await body()
    }

    /// Bytes the pending install needs: the archive plus the downloads its recipes declare.
    func requiredBytes(_ pending: PendingPluginInstall) -> Int64 {
        // Dependencies the preflight found already available download nothing.
        let available = Set((pending.preflight?.dependencies ?? []).filter { $0.state == .available }.map(\.id))
        let recipes = pending.plugin.manifest.dependencies
            .filter { $0.install != nil && !available.contains($0.id) }.compactMap(\.estimatedBytes)
        return recipes.reduce(0, +) + Int64(pending.archive?.version.size ?? 0)
    }

    /// Preflight never executes a pending archive or folder before installation approval.
    func runPreflight() {
        guard let pending = pendingInstall, pending.preflight == nil, !pending.plugin.manifest.dependencies.isEmpty else { return }
        pendingInstall?.preflight = .notChecked(pending.plugin, reason: "Checked after installation approval")
    }

    /// Dependencies that are missing and that no recipe installs: the plugin cannot run on this Mac.
    func unavailableDependencies(_ pending: PendingPluginInstall) -> [String] {
        (pending.preflight?.dependencies ?? []).filter { $0.state == .failed }.map(\.name)
    }

    /// Why the pending install cannot start (a dependency this Mac lacks, or not enough free space), or nil.
    func installBlocker(_ pending: PendingPluginInstall) -> String? {
        let unavailable = unavailableDependencies(pending)
        if !unavailable.isEmpty {
            return String(
                format: String(localized: "This plugin cannot run on this Mac: %@ is missing and the plugin does not install it"),
                unavailable.joined(separator: ", "))
        }
        let needed = requiredBytes(pending)
        guard needed > 0, let free = PluginFolders.availableBytes(), Double(needed) * 1.2 > Double(free) else { return nil }
        let format = ByteCountFormatter()
        return String(
            format: String(localized: "Needs about %@ but only %@ is free"),
            format.string(fromByteCount: needed), format.string(fromByteCount: free))
    }

    /// Installs (or, with `repair`, re-runs the dependency recipes of) the plugin the user approved, as a job with
    /// progress and Cancel. Recipes run in the plugin's filtered environment and process group.
    func installPendingPlugin() {
        guard var pending = pendingInstall, !installing else { return }
        if pending.local != nil {
            pending.scope = installScope
            pending.mode = mode(of: pending)
            pending.replacing = replaces(pending)
        }
        if let blocker = installBlocker(pending) {
            message = blocker
            return
        }
        let name = pending.plugin.manifest.displayName
        installing = true
        installProgress = nil
        installLog = []
        installStep = pending.repair ? String(localized: "Setting up…") : String(localized: "Installing…")
        self.pendingInstall = nil
        let work: @MainActor (JobReporter?) async throws -> JSONValue = { [weak self] reporter in
            guard let self else { throw CancellationError() }
            try await performInstall(pending, reporter: reporter)
            return .object(["plugin": .string(pending.plugin.id)])
        }
        let finished: @MainActor (Result<JSONValue, any Error>) -> Void = { [weak self] outcome in
            guard let self else { return }
            installing = false
            installJob = nil
            pending.archive?.discard()
            pending.local?.discard()
            switch outcome {
            case .success:
                message = pending.repair ? String(format: String(localized: "%@ is set up"), name)
                    : pending.mode == .link ? String(format: String(localized: "%@ is linked; use Reload after you edit it"), name)
                    : pending.replacing ? String(localized: "Plugin updated") : String(localized: "Plugin installed")
            case .failure(let error) where JobCenter.isCancellation(error):
                message = String(localized: "Plugin installation cancelled")
            case .failure(let error):
                message = error.localizedDescription
            }
            refresh(projectRoot: projectRoot)
        }
        if let jobs {
            installJob = jobs.start(
                pending.repair ? "plugins.setup" : "plugins.install", author: .user, detail: name,
                work: { reporter in try await work(reporter) }, finished: finished)
        } else {
            Task { do { finished(.success(try await work(nil))) } catch { finished(.failure(error)) } }
        }
    }

    func cancelInstall() {
        if let installJob { jobs?.cancel(installJob) }
    }

    private func performInstall(_ pending: PendingPluginInstall, reporter: JobReporter?) async throws {
        let plugin = pending.plugin
        let recipes = plugin.manifest.dependencies.compactMap { dependency in dependency.install.map { (dependency, $0) } }
        PluginFolders.prepare(plugin.id)
        let report: @Sendable (PluginRecipeOutput) -> Void = { [weak self] output in
            Task { @MainActor in self?.recipeOutput(output, reporter: reporter) }
        }
        if pending.repair {
            try trust.validateSetup(of: plugin)
            for (index, (dependency, recipe)) in recipes.enumerated() {
                installStep = String(format: String(localized: "Setting up %@ (%d of %d)…"), dependency.name, index + 1, recipes.count)
                try await PluginRecipeRunner.run(recipe.command, plugin: plugin, directory: plugin.directory, output: report)
            }
            // Approving the setup ran the plugin's own code, so its files are pinned like an install from the
            // registry; before, a plugin set up this way (a linked or copied folder) still said "Not approved yet".
            if trust.availability(of: plugin) == .untrusted { try trust.trust(plugin) }
            await checkHealthNow(plugin)
            return
        }
        let source = plugin.directory
        let manifest = plugin.manifest
        guard let installRoot = installRoot(for: pending.scope) else {
            throw PluginError.invalid("Open or save a project to add a plugin to it")
        }
        let destination = installRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let replacing = pending.replacing
        let stagingRoot = installRoot.appendingPathComponent(".staging-\(UUID().uuidString)")
        let staged = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }
        // Link (developer mode) places a link to the developer's folder, once it still holds the reviewed files.
        let linkTarget = pending.mode == .link ? pending.local : nil
        try await Task.detached {
            let manager = FileManager.default
            try manager.createDirectory(at: installRoot, withIntermediateDirectories: true)
            guard replacing || !manager.fileExists(atPath: destination.path) else {
                throw PluginError.invalid("Plugin \(manifest.id) is already installed")
            }
            try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            if let linkTarget, let folder = linkTarget.sourceFolder {
                try linkTarget.checkSourceUnchanged()
                try manager.createSymbolicLink(at: staged, withDestinationURL: folder.resolvingSymlinksInPath())
            } else {
                try manager.copyItem(at: source, to: staged)
            }
            _ = try InstalledPlugin(manifest: manifest, directory: staged).entrypointURL()
        }.value
        let stagedPlugin = InstalledPlugin(manifest: manifest, directory: staged)
        for (index, (dependency, recipe)) in recipes.enumerated() {
            installStep = String(format: String(localized: "Setting up %@ (%d of %d)…"), dependency.name, index + 1, recipes.count)
            try await PluginRecipeRunner.run(recipe.command, plugin: stagedPlugin, directory: staged, output: report)
        }
        try Task.checkCancellation()
        if replacing { stopSession(manifest.id) }
        try await Task.detached { try Self.place(staged, at: destination, root: installRoot) }.value
        // The user approved these exact files: pin them so later changes need approval again.
        if let installed = PluginCatalog.discover(in: [installRoot]).plugins.first(where: { $0.id == manifest.id }) {
            var origin = pending.local?.origin
            origin?.installedAt = Date()
            try? sources.set(origin, for: installed.directory)
            try trust.trust(installed)
            await checkHealthNow(installed)
        }
    }

    private func recipeOutput(_ output: PluginRecipeOutput, reporter: JobReporter?) {
        switch output {
        case .progress(let value, let text):
            installProgress = value
            if let text { installStep = text }
            reporter?.progress(value, detail: text)
        case .line(let text):
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            installLog.append(text)
            if installLog.count > 500 { installLog.removeFirst(installLog.count - 500) }
            reporter?.detail(text)
        }
    }
}
