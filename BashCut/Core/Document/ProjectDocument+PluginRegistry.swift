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
        handle("plugins.validate") { _, arguments, _ in
            let url = URL(fileURLWithPath: try arguments.string("path"))
            return await Task.detached { PluginLocalSource.validate(url).json }.value
        }
        handleAuthored("plugins.install") { document, arguments, author in
            if let path = arguments.optionalString("path") {
                guard arguments.optionalString("plugin") == nil, arguments.optionalString("version") == nil else {
                    throw RPCFailure(-32602, "Give either a registry plugin or path, not both")
                }
                return try document.requestLocalPluginInstall(
                    URL(fileURLWithPath: path), scope: PluginInstallScope(rawValue: arguments.optionalString("scope") ?? "user")
                        ?? .user, author: author)
            }
            guard let id = arguments.optionalString("plugin") else {
                throw RPCFailure(-32602, "Give a registry plugin ID or a path")
            }
            guard arguments.optionalString("scope") == nil else {
                throw RPCFailure(-32602, "scope is only for path; registry plugins install for this Mac")
            }
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

    /// `plugins install --path`: checks and copies the plugin as a job, then shows the approval only the user can give.
    private func requestLocalPluginInstall(_ url: URL, scope: PluginInstallScope, author: Author) throws -> JSONValue {
        let name = url.lastPathComponent
        let job = jobs.start("plugins.install", author: author, detail: name, work: { [weak self] reporter in
            guard let self else { throw CancellationError() }
            reporter.detail("Checking \(name)")
            try await plugins.requestLocalInstall(from: url, scope: scope)
            ui.showPlugins = true
            let plugin = plugins.pendingInstall?.plugin
            return .object([
                "plugin": plugin.map { .string($0.id) } ?? .null, "version": plugin.map { .string($0.manifest.version) } ?? .null,
                "scope": .string(scope.rawValue), "approval": .string("pending"),
            ])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = name + ": " + error.localizedDescription
        })
        return .object(["job": .string(job), "state": .string("running")])
    }
}

extension PluginValidation {
    var json: JSONValue {
        .object([
            "valid": .bool(isValid), "kind": kind.map { .string($0.rawValue) } ?? .null,
            "id": manifest.map { .string($0.id) } ?? .null, "name": manifest.map { .string($0.displayName) } ?? .null,
            "version": manifest.map { .string($0.version) } ?? .null,
            "capabilities": .array((manifest?.capabilities ?? []).map(JSONValue.string)),
            "category": manifest.map { .string(PluginCategory.of($0).rawValue) } ?? .null,
            "problems": .array(problems.map(JSONValue.string)), "warnings": .array(warnings.map(JSONValue.string)),
            "sha256": sha256.map(JSONValue.string) ?? .null,
        ])
    }
}
