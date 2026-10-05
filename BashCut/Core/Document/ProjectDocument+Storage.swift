import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Settings › Storage and `storage get` / `storage clear`: what BashCut keeps on disk and clearing what can be
/// made or downloaded again.
extension ProjectDocument {
    func storageEntries() async -> [StorageEntry] {
        let root = fileURL?.deletingLastPathComponent()
        let plugins = plugins.service.roots.user
        return await Task.detached { StorageUsage.measure(projectRoot: root, pluginsFolder: plugins) }.value
    }

    /// Clears one entry: stops the plugin's session first for plugin data (every plugin's for the shared runtimes),
    /// and rebuilds the preview after proxies.
    func clearStorage(_ entry: StorageEntry) async throws {
        if let pluginID = entry.pluginID {
            plugins.stopSession(pluginID)
            plugins.health[pluginID] = nil
        }
        if entry.kind == .sharedData {
            for plugin in plugins.plugins { plugins.stopSession(plugin.id) }
            plugins.health = [:]
        }
        if entry.kind == .proxies, !proxies.active.isEmpty {
            throw StorageUsageError("Wait for the preview proxies being made to finish")
        }
        if entry.kind == .rampAudio {
            guard !exports.isRunning else { throw StorageUsageError(String(localized: "Wait for exports to finish before clearing ramp audio")) }
            try await preview.maintainCache {
                try await Task.detached { try StorageUsage.clear(entry) }.value
            }
        } else {
            try await Task.detached { try StorageUsage.clear(entry) }.value
        }
        if entry.kind == .proxies { rebuild() }
        DebugLog.write("storage", "cleared \(entry.id) (\(entry.bytes) bytes)")
    }

    static func storageJSON(_ entry: StorageEntry) -> JSONValue {
        .object([
            "kind": .string(entry.kind.rawValue), "plugin": entry.pluginID.map(JSONValue.string) ?? .null,
            "path": .string(entry.url.path), "bytes": .integer(Int(entry.bytes)), "clearable": .bool(entry.clearable),
        ])
    }

    func registerStorageCommands() {
        handle("storage.get") { document, _, _ in
            let entries = await document.storageEntries()
            let plugins = StorageUsage.byPlugin(entries)
            return .object([
                // Plugin entries in the same largest-first order as `plugins`, then the rest.
                "entries": .array((plugins.flatMap(\.entries) + entries.filter { $0.pluginID == nil }).map(Self.storageJSON)),
                "plugins": .array(plugins.map { plugin in
                    .object([
                        "plugin": .string(plugin.pluginID), "bytes": .integer(Int(plugin.bytes)),
                        "installed": .bool(plugin.installed),
                    ])
                }),
                "totalBytes": .integer(Int(entries.reduce(0) { $0 + $1.bytes })),
            ])
        }
        handleAuthored("storage.clear") { document, arguments, _ in
            let kind = try arguments.string("target")
            let plugin = arguments.optionalString("plugin")
            let matches = await document.storageEntries().filter { entry in
                entry.kind.rawValue == kind && entry.clearable && (plugin == nil || entry.pluginID == plugin)
            }
            if kind == StorageEntry.Kind.pluginData.rawValue, plugin == nil {
                throw RPCFailure(-32602, "Name the plugin whose data to delete (--plugin); it must be set up again after")
            }
            var cleared: [JSONValue] = []
            for entry in matches {
                do { try await document.clearStorage(entry) } catch { throw RPCFailure(-32003, error.localizedDescription) }
                cleared.append(Self.storageJSON(entry))
            }
            return .object(["cleared": .array(cleared), "bytes": .integer(Int(matches.reduce(0) { $0 + $1.bytes }))])
        }
    }
}
