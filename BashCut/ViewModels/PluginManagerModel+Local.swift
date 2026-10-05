import AppKit
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import Foundation
import UniformTypeIdentifiers

/// Where an install from this Mac goes: every project (the user plugin folder) or only the open project
/// (`<project>/.bashcut/plugins/`, which travels with it). Registry installs always go to the user folder.
enum PluginInstallScope: String, CaseIterable, Identifiable {
    case user, project
    var id: String { rawValue }
    var title: String {
        switch self {
        case .user: String(localized: "This Mac")
        case .project: String(localized: "This project")
        }
    }
}

/// Add Plugin…: plugins from a folder, plugin.json or zip on this Mac, or from a link, instead of the registry (#83).
extension PluginManagerModel {
    /// Account under which link access tokens are kept in the Keychain, one per host.
    nonisolated static let linkTokenAccount = "link-token"

    /// Add Plugin…: a sheet to paste a link or choose a file or folder.
    func addPlugin() {
        guard PluginChannel.current.allowsUserPlugins else {
            message = Self.channelRefusal
            return
        }
        tab = .installed
        showAddPlugin = true
    }

    /// Choose a plugin folder, its plugin.json, or a .zip / .bashcutplugin archive.
    func chooseLocalPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .json] + [UTType(filenameExtension: "bashcutplugin")].compactMap { $0 }
        panel.message = String(localized: "Choose a plugin folder, its plugin.json, or a .zip or .bashcutplugin file")
        guard let url = ModalCenter.shared.open(panel, name: "choose-plugin")?.first else { return }
        showAddPlugin = false
        Task { await addPlugin(from: url) }
    }

    /// Adds the plugin at `url` (from the open panel or a drop), showing problems in the sheet's message line.
    func addPlugin(from url: URL) async {
        do { try await requestLocalInstall(from: url) } catch { message = error.localizedDescription }
    }

    /// Checks and copies a plugin from this Mac, then shows the install approval. Nothing runs before the user
    /// approves it, and only the user can.
    @discardableResult
    func requestLocalInstall(from url: URL, scope: PluginInstallScope = .user) async throws -> InstalledPlugin {
        try checkCanAdd(scope: scope)
        let parent = service.roots.user
        let staged = try await Task.detached { try PluginLocalSource.stage(url, stagingParent: parent) }.value
        present(staged, scope: scope)
        return staged.plugin
    }

    /// Downloads a plugin from a link, checks it, then shows the install approval. The access token for the link's
    /// host comes from the Keychain.
    @discardableResult
    func requestLinkInstall(_ link: PluginLink, scope: PluginInstallScope = .user) async throws -> InstalledPlugin {
        try checkCanAdd(scope: scope)
        guard !addingLink else { throw PluginError.invalid("A plugin link is already downloading") }
        addingLink = true
        defer { addingLink = false }
        let parent = service.roots.user
        let staged = try await linkResolver.stage(link, stagingParent: parent)
        present(staged, scope: scope)
        return staged.plugin
    }

    /// Checks a link without installing it (`plugins validate --url`).
    func validateLink(_ link: PluginLink) async -> PluginValidation { await linkResolver.validate(link) }

    private var linkResolver: PluginLinkResolver {
        let secrets = secrets
        return PluginLinkResolver { host in
            let token = secrets.read(plugin: Self.linkTokenAccount, option: host)
            return token.isEmpty ? nil : token
        }
    }

    func hasLinkToken(for host: String) -> Bool { !secrets.read(plugin: Self.linkTokenAccount, option: host).isEmpty }

    /// Saves the access token for `host` in the Keychain; an empty token removes it.
    func setLinkToken(_ token: String, for host: String) throws {
        try secrets.write(token.trimmingCharacters(in: .whitespacesAndNewlines), plugin: Self.linkTokenAccount, option: host)
    }

    private func checkCanAdd(scope: PluginInstallScope) throws {
        guard PluginChannel.current.allowsUserPlugins else { throw PluginError.invalid(Self.channelRefusal) }
        guard scope == .user || currentProjectRoot != nil else {
            throw PluginError.invalid("Open or save a project to add a plugin to it")
        }
    }

    private func present(_ staged: StagedLocalPlugin, scope: PluginInstallScope) {
        cancelPendingInstall()
        installScope = scope
        var pending = PendingPluginInstall(plugin: staged.plugin, local: staged, scope: scope)
        pending.replacing = replaces(pending)
        if !staged.plugin.manifest.dependencies.isEmpty {
            pending.preflight = .notChecked(staged.plugin, reason: "Checked after installation approval")
        }
        tab = .installed
        guard showAddPlugin else {
            pendingInstall = pending
            return
        }
        // One sheet at a time: let Add Plugin close before the approval opens.
        showAddPlugin = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, pendingInstall == nil else {
                pending.local?.discard()
                return
            }
            pendingInstall = pending
        }
    }

    var sources: PluginSourceStore { PluginSourceStore(userRoot: service.roots.user) }

    /// Where a plugin installed from a link came from.
    func origin(of plugin: InstalledPlugin) -> PluginLinkOrigin? { sources.origin(of: plugin.directory) }

    /// The plugin folder an install with `scope` goes to, or nil for a project scope without a saved project.
    func installRoot(for scope: PluginInstallScope) -> URL? {
        switch scope {
        case .user: service.roots.user
        case .project: currentProjectRoot?.appendingPathComponent(".bashcut/plugins", isDirectory: true)
        }
    }

    /// Where `pending` goes if approved now: the scope chosen in the approval for a plugin from this Mac or a link.
    func scope(of pending: PendingPluginInstall) -> PluginInstallScope {
        pending.local == nil ? pending.scope : installScope
    }

    /// Whether installing replaces a copy already in the chosen folder.
    func replaces(_ pending: PendingPluginInstall) -> Bool {
        guard let root = installRoot(for: scope(of: pending)) else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(pending.plugin.id).path)
    }

    /// Which copy runs when another one with the same id is installed elsewhere: project > this Mac > BashCut's
    /// own, except that BashCut's copy wins when it is newer.
    func shadowNote(_ pending: PendingPluginInstall) -> String? {
        guard pending.local != nil, let root = installRoot(for: scope(of: pending)),
            let other = plugins.first(where: { $0.id == pending.plugin.id }),
            other.directory.deletingLastPathComponent().standardizedFileURL != root.standardizedFileURL
        else { return nil }
        let version = other.manifest.version
        if trust.isBundled(other) {
            let newer = (SemanticVersion(version) ?? .zero) > (SemanticVersion(pending.plugin.manifest.version) ?? .zero)
            return newer
                ? String(format: String(localized: "BashCut comes with a newer copy (%@), which is used instead"), version)
                : String(format: String(localized: "Used instead of the copy that comes with BashCut (%@)"), version)
        }
        if scope(of: pending) == .project {
            return String(format: String(localized: "Used in this project instead of the copy on this Mac (%@)"), version)
        }
        return String(format: String(localized: "This project has its own copy (%@), which is used while it is open"), version)
    }
}
