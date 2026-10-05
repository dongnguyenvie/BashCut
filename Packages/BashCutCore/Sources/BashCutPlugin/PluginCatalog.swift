import CryptoKit
import Foundation

public struct InstalledPlugin: Sendable, Equatable, Identifiable {
    public let manifest: PluginManifest
    public let directory: URL
    public var id: String { manifest.id }
    /// Approvals and local settings belong to one installation, never every copy sharing its manifest ID.
    public var installationID: String {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(root.utf8)).map { String(format: "%02x", $0) }.joined()
        return id + "@" + digest
    }
    public init(manifest: PluginManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }

    public func entrypointURL() throws -> URL {
        try manifest.validate()
        let entrypoint = directory.appendingPathComponent(manifest.entrypoint).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: entrypoint.path) else {
            throw PluginError.invalid("Plugin entrypoint is missing or is not executable")
        }
        return entrypoint
    }

    /// The folder of a sticker pack, or nil when it is missing or resolves outside the plugin (a symlink out).
    public func stickerFolder(_ pack: PluginStickerPack) -> URL? {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let folder = directory.appendingPathComponent(pack.path, isDirectory: true).resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard folder.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return folder
    }
}

public struct PluginCatalogResult: Sendable {
    public let plugins: [InstalledPlugin]
    public let diagnostics: [String]
}

public enum PluginCatalog {
    /// Earlier roots win: project plugins can override user plugins, which can override bundled plugins. A plugin
    /// in `bundled` (inside the app) is overridden only by a higher version, so a stale download never hides the
    /// newer copy an app update brought.
    public static func discover(in roots: [URL], bundled: URL? = nil) -> PluginCatalogResult {
        let bundledPath = bundled?.standardizedFileURL.path
        let manager = FileManager.default
        var plugins: [String: InstalledPlugin] = [:]
        var diagnostics: [String] = []
        let decoder = JSONDecoder()
        for root in roots {
            let directories = ((try? manager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []).sorted { $0.path < $1.path }
            for directory in directories {
                let manifestURL = directory.appendingPathComponent("plugin.json")
                guard manager.fileExists(atPath: manifestURL.path) else { continue }
                do {
                    let manifest = try decoder.decode(
                        PluginManifest.self, from: Data(contentsOf: manifestURL))
                    try manifest.validate()
                    if let earlier = plugins[manifest.id] {
                        let newer = root.standardizedFileURL.path == bundledPath
                            && (SemanticVersion(manifest.version) ?? .zero) > (SemanticVersion(earlier.manifest.version) ?? .zero)
                        guard newer else {
                            diagnostics.append("\(earlier.directory.path) shadows installed plugin \(manifest.id) at \(directory.path)")
                            continue
                        }
                        let plugin = InstalledPlugin(manifest: manifest, directory: directory)
                        _ = try plugin.entrypointURL()
                        diagnostics.append(
                            "\(manifest.id) \(earlier.manifest.version) at \(earlier.directory.path) is older than the "
                                + "copy in BashCut (\(manifest.version)); using BashCut's")
                        plugins[manifest.id] = plugin
                        continue
                    }
                    let plugin = InstalledPlugin(manifest: manifest, directory: directory)
                    _ = try plugin.entrypointURL()
                    plugins[manifest.id] = plugin
                } catch {
                    diagnostics.append("\(manifestURL.path): \(error.localizedDescription)")
                }
            }
        }
        return PluginCatalogResult(
            plugins: plugins.values.sorted { $0.manifest.displayName < $1.manifest.displayName },
            diagnostics: diagnostics)
    }
}
