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
    /// Why each plugin may or may not run.
    var availability: [String: PluginAvailability] = [:]
    /// Actions of runnable plugins, in catalog order.
    var actions: [ContributedAction] = []
    /// Most recent hook deliveries, newest last.
    var hookLog: [PluginHookRun] = []
    var proposals: [PluginProposal] = []
    /// The action whose parameter sheet is open.
    var pendingAction: PendingPluginAction?
    @ObservationIgnored let trust: PluginTrustStore
    @ObservationIgnored let service: CapabilityService
    private var projectRoot: URL?
    static let hookLogLimit = 200

    init(trust: PluginTrustStore = .standard) {
        self.trust = trust
        service = CapabilityService(trust: trust)
    }

    private var userRoot: URL { service.roots.user }

    func refresh(projectRoot: URL?) {
        self.projectRoot = projectRoot
        let result = service.catalog(projectRoot: projectRoot)
        plugins = result.plugins
        diagnostics = result.diagnostics
        health = health.filter { id, _ in plugins.contains(where: { $0.id == id }) }
        availability = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, service.availability($0)) })
        rebuildActions()
    }

    private func rebuildActions() {
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
    }

    func action(_ id: String) -> ContributedAction? { actions.first { $0.id == id } }

    func actions(at placement: String) -> [ContributedAction] {
        actions.filter { $0.spec.placements.contains(placement) }
    }

    /// Plugins whose hooks receive `event` now.
    func subscribers(for event: PluginEvent) -> [(InstalledPlugin, PluginHookContribution)] {
        plugins.compactMap { plugin in
            guard availability[plugin.id] == .ready, trust.hooksEnabled(plugin.id),
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
        do { try trust.revoke(plugin.id) } catch { message = error.localizedDescription }
        stopSession(plugin.id)
        refresh(projectRoot: projectRoot)
    }

    func setEnabled(_ plugin: InstalledPlugin, enabled: Bool? = nil, hooks: Bool? = nil) throws {
        try trust.setEnabled(plugin, enabled: enabled, hooks: hooks)
        if enabled == false { stopSession(plugin.id) }
        refresh(projectRoot: projectRoot)
    }

    func isEnabled(_ plugin: InstalledPlugin) -> Bool { trust.grant(for: plugin.id)?.enabled ?? true }

    private func stopSession(_ pluginID: String) {
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

    func providers(for capability: String) -> [PluginProviderChoice] {
        plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).compactMap { provider in
                guard provider.capability == capability else { return nil }
                return PluginProviderChoice(
                    pluginID: plugin.id, pluginName: plugin.manifest.displayName, provider: provider)
            }
        }.sorted {
            ($0.provider.priority, $0.provider.name) > ($1.provider.priority, $1.provider.name)
        }
    }

    /// Marks a capability busy for the UI while `body` runs. A capability runs one request at a time.
    func running<T>(_ capability: String, _ body: () async throws -> T) async throws -> T {
        guard calling.insert(capability).inserted else {
            throw PluginError.invalid("\(capability) is already running")
        }
        defer { calling.remove(capability) }
        return try await body()
    }

    func choosePlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a BashCut plugin folder containing plugin.json")
        guard let directory = ModalCenter.shared.open(panel, name: "choose-plugin")?.first else { return }
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
                // The user approved these exact files: pin them so later changes need approval again.
                if let installed = PluginCatalog.discover(in: [installRoot]).plugins.first(where: { $0.id == manifest.id }) {
                    try trust.trust(installed)
                }
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
