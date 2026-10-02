import AppKit
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
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

/// UI state for the plugin catalog. Capability calls go through `CapabilityService`, which the
/// document and automation commands share; this model only tracks which capabilities are running.
@MainActor @Observable final class PluginManagerModel {
    var plugins: [InstalledPlugin] = []
    var diagnostics: [String] = []
    var pendingInstall: PendingPluginInstall?
    var installing = false
    var message = ""
    var health: [String: PluginHealth] = [:]
    var checking: Set<String> = []
    var calling: Set<String> = []
    @ObservationIgnored let service = CapabilityService()
    private var projectRoot: URL?

    private var userRoot: URL { service.roots.user }

    func refresh(projectRoot: URL?) {
        self.projectRoot = projectRoot
        let result = service.catalog(projectRoot: projectRoot)
        plugins = result.plugins
        diagnostics = result.diagnostics
        health = health.filter { id, _ in plugins.contains(where: { $0.id == id }) }
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
                    pluginID: plugin.id, pluginName: plugin.manifest.name, provider: provider)
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
