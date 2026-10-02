import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// One registry plugin as Browse and Updates show it.
struct PluginListing: Identifiable {
    enum Status: Equatable {
        case available
        case installed
        case update(from: String)
        /// Installed in the project folder or the app, which an install in the user folder would not replace.
        case shadowed
        case incompatible(String)
    }

    let entry: PluginRegistryEntry
    let version: PluginRegistryVersion?
    let installed: InstalledPlugin?
    let status: Status
    var id: String { entry.id }

    var json: JSONValue {
        var statusText: String
        switch status {
        case .available: statusText = "available"
        case .installed: statusText = "installed"
        case .update: statusText = "update"
        case .shadowed: statusText = "installed-elsewhere"
        case .incompatible: statusText = "incompatible"
        }
        var fields: [String: JSONValue] = [
            "id": .string(entry.id), "name": .string(entry.name.text), "status": .string(statusText),
            "summary": entry.summary.map { .string($0.text) } ?? .null,
            "publisher": entry.publisher.map(JSONValue.string) ?? .null,
            "category": entry.category.map(JSONValue.string) ?? .null,
            "capabilities": .array((entry.capabilities ?? []).map(JSONValue.string)),
            "version": version.map { .string($0.version) } ?? .null,
            "installedVersion": installed.map { .string($0.manifest.version) } ?? .null,
            "size": version?.size.map(JSONValue.integer) ?? .null,
        ]
        if case .incompatible(let reason) = status { fields["reason"] = .string(reason) }
        return .object(fields)
    }
}

/// The remote catalog: browsing, installing, updating and removing plugins from `registry.json`.
extension PluginManagerModel {
    /// `defaults write app.bashcut pluginRegistryURL <url>` points BashCut at another registry (testing, private).
    static var registryURL: URL {
        UserDefaults.standard.string(forKey: "pluginRegistryURL").flatMap(URL.init(string:)) ?? PluginRegistryClient.defaultURL
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// Fetches the registry (or reuses a fresh cached copy). Failures keep the cached copy and set `registryError`.
    func refreshRegistry(force: Bool = false) async {
        guard !loadingRegistry else { return }
        loadingRegistry = true
        defer { loadingRegistry = false }
        do {
            let snapshot = try await registryClient.snapshot(force: force)
            registry = snapshot.document
            registryFetchedAt = snapshot.fetchedAt
            registryError = snapshot.staleReason
        } catch {
            registryError = error.localizedDescription
        }
    }

    /// Registry plugins matching `query` and `capability`, with what installing would do.
    func listings(query: String = "", capability: String? = nil) -> [PluginListing] {
        (registry?.plugins ?? []).filter { entry in
            entry.matches(query) && (capability.map { (entry.capabilities ?? []).contains($0) } ?? true)
        }.map(listing).sorted { $0.entry.name.text.localizedCaseInsensitiveCompare($1.entry.name.text) == .orderedAscending }
    }

    var updates: [PluginListing] {
        listings().filter { if case .update = $0.status { true } else { false } }
    }

    func listing(_ entry: PluginRegistryEntry) -> PluginListing {
        let installed = plugins.first { $0.id == entry.id }
        switch entry.resolve(appVersion: Self.appVersion) {
        case .failure(let error):
            return PluginListing(entry: entry, version: nil, installed: installed, status: .incompatible(error.localizedDescription))
        case .success(let version):
            guard let installed else { return PluginListing(entry: entry, version: version, installed: nil, status: .available) }
            guard isUserInstalled(installed) else {
                return PluginListing(entry: entry, version: version, installed: installed, status: .shadowed)
            }
            let current = SemanticVersion(installed.manifest.version) ?? .zero
            let status: PluginListing.Status = (SemanticVersion(version.version) ?? .zero) > current
                ? .update(from: installed.manifest.version) : .installed
            return PluginListing(entry: entry, version: version, installed: installed, status: status)
        }
    }

    /// Plugins in the user or project folder can be removed; plugins inside the app can only be turned off.
    func isRemovable(_ plugin: InstalledPlugin) -> Bool { !trust.isBundled(plugin) }

    func isUserInstalled(_ plugin: InstalledPlugin) -> Bool {
        plugin.directory.standardizedFileURL.path.hasPrefix(service.roots.user.standardizedFileURL.path + "/")
    }

    /// Downloads and verifies a registry plugin, then shows the install approval. Nothing runs before the user
    /// approves it.
    func requestInstall(_ id: String, version requested: String? = nil) async throws {
        if registry == nil { await refreshRegistry() }
        guard let entry = registry?.entry(id) else { throw PluginError.invalid("No plugin \(id) in the registry") }
        let version: PluginRegistryVersion
        if let requested {
            guard let match = entry.versions.first(where: { $0.version == requested }) else {
                throw PluginError.invalid("\(id) has no version \(requested) in the registry")
            }
            version = match
        } else {
            version = try entry.resolve(appVersion: Self.appVersion).get()
        }
        guard downloading.insert(id).inserted else { throw PluginError.invalid("\(id) is already downloading") }
        defer { downloading.remove(id) }
        #if DEBUG
            // Development builds can test a local registry (`pluginRegistryURL` = file://…) end to end.
            let allowFiles = Self.registryURL.isFileURL
        #else
            let allowFiles = false
        #endif
        let installer = PluginArchiveInstaller(stagingParent: service.roots.user, allowFileURLs: allowFiles)
        let staged = try await installer.stage(entry, version: version)
        cancelPendingInstall()
        let installed = plugins.first { $0.id == id && isUserInstalled($0) }
        var pending = PendingPluginInstall(plugin: staged.plugin, archive: staged, replacing: installed != nil)
        if !staged.plugin.manifest.dependencies.isEmpty { pending.preflight = await service.health(staged.plugin) }
        pendingInstall = pending
        tab = .browse
    }

    /// Drops the install waiting for approval and its download.
    func cancelPendingInstall() {
        pendingInstall?.archive?.discard()
        pendingInstall = nil
    }

    /// Shows the approval to run an installed plugin's dependency recipes again.
    func requestSetup(_ plugin: InstalledPlugin) {
        cancelPendingInstall()
        pendingInstall = PendingPluginInstall(plugin: plugin, repair: true)
        tab = .installed
        runPreflight()
    }

    /// Uninstalls a plugin from the user or project plugin folder, with its trust grant and user options, and with
    /// `deleteData` also its data and cache folders (environments, models).
    func removePlugin(_ plugin: InstalledPlugin, deleteData: Bool = false) throws {
        guard isRemovable(plugin) else {
            throw PluginError.invalid("Plugins that come with BashCut cannot be removed; turn them off instead")
        }
        stopSession(plugin.id)
        try FileManager.default.removeItem(at: plugin.directory)
        try? trust.revoke(plugin.id)
        for key in trust.userOptions(plugin.id).keys { try? trust.setUserOption(plugin.id, key: key, value: nil) }
        if deleteData { try PluginFolders.remove(plugin.id) }
        health[plugin.id] = nil
        message = String(format: String(localized: "Removed %@"), plugin.manifest.displayName)
        refresh(projectRoot: currentProjectRoot)
    }
}
