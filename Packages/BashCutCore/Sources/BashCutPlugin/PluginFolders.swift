import Foundation

/// Where plugins keep state outside their (replaceable) bundle folder:
///
/// - data: `~/Library/Application Support/BashCut/PluginData/<id>/` — environments, settings, anything costly
///   to rebuild; kept across plugin updates.
/// - cache: `~/Library/Caches/BashCut/PluginData/<id>/` — downloads such as models that can be fetched again.
///
/// The app passes them as `BASHCUT_PLUGIN_DATA` and `BASHCUT_PLUGIN_CACHE`, creates them, shows their size and
/// offers to delete them when the plugin is removed. `BASHCUT_PLUGIN_STATE_ROOT` relocates both (tests).
///
/// Every plugin also gets two shared folders, `_shared` under each root (`BASHCUT_SHARED_DATA`,
/// `BASHCUT_SHARED_CACHE`), so plugins built on the same runtime keep one copy of it: a shared Python install and
/// uv's package cache, for example. `_` cannot start a plugin ID, so the name never clashes with one.
public enum PluginFolders {
    private static var overrideRoot: URL? {
        ProcessInfo.processInfo.environment["BASHCUT_PLUGIN_STATE_ROOT"].map { URL(fileURLWithPath: $0) }
    }

    public static var dataRoot: URL {
        if let overrideRoot { return overrideRoot.appendingPathComponent("data", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/PluginData", isDirectory: true)
    }

    public static var cacheRoot: URL {
        if let overrideRoot { return overrideRoot.appendingPathComponent("cache", isDirectory: true) }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/PluginData", isDirectory: true)
    }

    /// The saved copy of the plugin registry: `~/Library/Caches/BashCut/Registry/`. It is fetched again when
    /// missing, so it lives in Caches (not backed up) rather than Application Support, where it was before #101.
    public static var registryCache: URL {
        if let overrideRoot { return overrideRoot.appendingPathComponent("registry", isDirectory: true) }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/Registry", isDirectory: true)
    }

    /// Plugins that come with the app: `Contents/Resources/Plugins/`. Not `Contents/PlugIns`, which codesign
    /// reserves for code bundles; each core plugin's executable is signed on its own before the app.
    public static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true) }

    public static func data(_ pluginID: String) -> URL { dataRoot.appendingPathComponent(pluginID, isDirectory: true) }
    public static func cache(_ pluginID: String) -> URL { cacheRoot.appendingPathComponent(pluginID, isDirectory: true) }

    /// The folder name of the shared data and cache under each root.
    public static let sharedName = "_shared"
    /// Runtimes several plugins use (Python installs): deleting it means setting those plugins up again.
    public static var sharedData: URL { dataRoot.appendingPathComponent(sharedName, isDirectory: true) }
    /// Downloads several plugins use (package caches): safe to clear, fetched again when needed.
    public static var sharedCache: URL { cacheRoot.appendingPathComponent(sharedName, isDirectory: true) }

    /// Creates the plugin's data and cache folders, and the shared ones.
    public static func prepare(_ pluginID: String) {
        for folder in [data(pluginID), cache(pluginID), sharedData, sharedCache] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    /// Bytes used by the plugin's data and cache folders.
    public static func usage(_ pluginID: String) -> Int64 {
        [data(pluginID), cache(pluginID)].reduce(0) { $0 + size(of: $1) }
    }

    /// Deletes the plugin's data and cache folders.
    public static func remove(_ pluginID: String) throws {
        for folder in [data(pluginID), cache(pluginID)] where FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    static func size(of folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Free space for new plugin data, as macOS reports it for important downloads.
    public static func availableBytes() -> Int64? {
        let probe = dataRoot.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}
