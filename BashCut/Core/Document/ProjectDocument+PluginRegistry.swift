import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import Foundation

/// The plugin registry from the editor: panels ask for a provider, automation searches and requests installs.
extension ProjectDocument {
    /// Opens Plugins › Browse, optionally narrowed to providers of `capability`.
    func showPluginBrowser(capability: String? = nil) {
        plugins.browseCapability = capability
        plugins.tab = .browse
        plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent())
        ui.showPlugins = true
        Task { await plugins.refreshRegistry() }
    }

    func registerPluginRegistryCommands() {
        handle("plugins.search") { document, arguments, _ in
            await document.plugins.refreshRegistry(force: arguments.bool("refresh"))
            guard document.plugins.registry != nil else {
                throw RPCFailure(-32003, document.plugins.registryError ?? "The plugin registry is unavailable")
            }
            let listings = document.plugins.listings(
                query: arguments.optionalString("query") ?? "", capability: arguments.optionalString("capability"),
                category: arguments.optionalString("category").flatMap(PluginCategory.init(rawValue:)))
            return .object([
                "plugins": .array(listings.map(\.json)),
                "registry": .string(PluginManagerModel.registryURL.absoluteString),
                "stale": document.plugins.registryError.map(JSONValue.string) ?? .null,
            ])
        }
        handle("plugins.updates") { document, _, _ in
            await document.plugins.refreshRegistry()
            return .array(document.plugins.updates.map(\.json))
        }
        handleAuthored("plugins.install") { document, arguments, author in
            let id = try arguments.string("plugin")
            let version = arguments.optionalString("version")
            let job = document.jobs.start("plugins.install", author: author, detail: id, work: { [weak document] reporter in
                guard let document else { throw CancellationError() }
                reporter.detail("Downloading \(id)")
                try await document.plugins.requestInstall(id, version: version)
                document.ui.showPlugins = true
                return .object(["plugin": .string(id), "approval": .string("pending")])
            }, finished: { [weak document] outcome in
                guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
                document?.message = id + ": " + error.localizedDescription
            })
            return .object(["job": .string(job), "state": .string("running")])
        }
        handleAuthored("plugins.remove") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            do {
                try document.plugins.removePlugin(plugin, deleteData: arguments.bool("data"))
            } catch { throw RPCFailure(-32602, error.localizedDescription) }
            return .object(["removed": .string(plugin.id), "data": .bool(arguments.bool("data"))])
        }
        handleAuthored("plugins.setup") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            guard plugin.manifest.dependencies.contains(where: { $0.install != nil }) else {
                throw RPCFailure(-32602, "\(plugin.id) has no install recipes")
            }
            try document.plugins.requestSetup(plugin)
            document.ui.showPlugins = true
            return .object(["plugin": .string(plugin.id), "approval": .string("pending")])
        }
    }
}
