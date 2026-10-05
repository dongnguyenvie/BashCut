import Crypto
import Foundation

public struct InstalledPlugin: Sendable, Equatable, Identifiable {
    public let manifest: PluginManifest
    public let directory: URL
    public var id: String { manifest.id }
    /// Approvals and local settings belong to one installation, never every copy sharing its manifest ID.
    /// Worked out once: it resolves links and hashes, and trust checks ask for it many times per refresh.
    public let installationID: String
    /// `directory` standardized, kept as a string: URL methods cost microseconds each, which adds up over a
    /// catalog of a thousand plugins.
    public let directoryPath: String
    public init(manifest: PluginManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
        directoryPath = directory.standardizedFileURL.path
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(root.utf8)).map { String(format: "%02x", $0) }.joined()
        installationID = manifest.id + "@" + digest
    }

    public func entrypointURL() throws -> URL {
        try manifest.validate()
        let entrypoint = directory.appendingPathComponent(manifest.entrypoint).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: entrypoint.path) else {
            throw PluginError.invalid("Plugin entrypoint is missing or is not executable")
        }
        return entrypoint
    }
}

public struct PluginCatalogResult: Sendable {
    public let plugins: [InstalledPlugin]
    public let diagnostics: [String]
}

public enum PluginCatalog {
    /// Earlier roots win: project plugins can override user plugins, which can override bundled plugins. A plugin
    /// in `bundled` (inside the app) is overridden only by a higher version, so a stale download never hides the
    /// newer copy an app update brought. With a `cache`, plugins whose plugin.json and entrypoint did not change
    /// since the last call are not read again.
    public static func discover(
        in roots: [URL], bundled: URL? = nil, cache: PluginCatalogCache? = nil
    ) -> PluginCatalogResult {
        let bundledPath = bundled?.standardizedFileURL.path
        let manager = FileManager.default
        var plugins: [String: InstalledPlugin] = [:]
        var diagnostics: [String] = []
        let decoder = JSONDecoder()
        for root in roots {
            // Names, not URLs: building a URL per folder costs more than reading a cached plugin.
            let rootPath = root.standardizedFileURL.path
            let names = ((try? manager.contentsOfDirectory(atPath: rootPath)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            for name in names {
                let path = rootPath + "/" + name
                let cached = cache?.plugin(at: path)
                guard cached != nil || manager.fileExists(atPath: path + "/plugin.json") else { continue }
                let directory = cached?.directory ?? URL(fileURLWithPath: path, isDirectory: true)
                do {
                    let manifestSignature = cached == nil ? PluginFileSignature(path: path + "/plugin.json") : nil
                    let manifest = try cached?.manifest ?? decoder.decode(
                        PluginManifest.self, from: Data(contentsOf: URL(fileURLWithPath: path + "/plugin.json")))
                    if cached == nil { try manifest.validate() }
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
                    if let cached {
                        plugins[manifest.id] = cached
                        continue
                    }
                    let plugin = InstalledPlugin(manifest: manifest, directory: directory)
                    let entrypointSignature = PluginFileSignature.manifestAndEntrypoint(of: plugin)[1]
                    _ = try plugin.entrypointURL()
                    cache?.store(plugin, signatures: [manifestSignature, entrypointSignature])
                    plugins[manifest.id] = plugin
                } catch {
                    diagnostics.append("\(path)/plugin.json: \(error.localizedDescription)")
                }
            }
        }
        // displayName looks up the current language, so it is read once per plugin, not once per comparison.
        let sorted = plugins.values.map { ($0.manifest.displayName, $0) }
            .sorted { ($0.0, $0.1.id) < ($1.0, $1.1.id) }.map(\.1)
        return PluginCatalogResult(plugins: sorted, diagnostics: diagnostics)
    }
}
