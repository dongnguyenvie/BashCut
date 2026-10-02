import Foundation

public struct InstalledPlugin: Sendable, Equatable, Identifiable {
    public let manifest: PluginManifest
    public let directory: URL
    public var id: String { manifest.id }
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
}

public struct PluginCatalogResult: Sendable {
    public let plugins: [InstalledPlugin]
    public let diagnostics: [String]
}

public enum PluginCatalog {
    /// Earlier roots win: project plugins can override user plugins, which can override bundled plugins.
    public static func discover(in roots: [URL]) -> PluginCatalogResult {
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
                    guard plugins[manifest.id] == nil else {
                        diagnostics.append("Ignored duplicate plugin \(manifest.id) at \(directory.path)")
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
            plugins: plugins.values.sorted { $0.manifest.name < $1.manifest.name },
            diagnostics: diagnostics)
    }
}
