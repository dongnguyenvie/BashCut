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
                throw RPCFailure(-32003, document.plugins.registryError ?? "The plugin registry is unavailable", category: .unavailable)
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
        handle("plugins.validate") { document, arguments, _ in
            switch try PluginSourceArgument(arguments) {
            case .path(let url): return await Task.detached { PluginLocalSource.validate(url).json }.value
            case .link(let link): return await document.plugins.validateLink(link).json
            case nil: throw RPCFailure(-32602, "Give a path or a url")
            }
        }
        handleAuthored("plugins.install") { document, arguments, author in
            try document.installPluginCommand(arguments, author: author)
        }
        handleAuthored("plugins.reload") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            let state = await document.plugins.reload(plugin)
            return .object([
                "plugin": .string(plugin.id), "availability": .string(state.name), "detail": .string(state.detail),
                "linked": document.plugins.linkTarget(of: plugin).map { .string($0.path) } ?? .null,
            ])
        }
        handleAuthored("plugins.replace") { document, arguments, author in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            guard let scope = document.plugins.installScope(of: plugin) else {
                throw RPCFailure(-32602, "Plugins that come with BashCut cannot be replaced")
            }
            let url = URL(fileURLWithPath: try arguments.string("path"))
            return document.requestAddedPluginInstall(.path(url), scope: scope, replacing: plugin, author: author)
        }
        handleAuthored("plugins.remove") { document, arguments, _ in
            let plugin = try document.requirePlugin(arguments.string("plugin"))
            do {
                try document.plugins.removePlugin(plugin, deleteData: arguments.bool("data"))
            } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
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

    /// `plugins install`: a registry plugin by ID, or a plugin from a path or link.
    private func installPluginCommand(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        if let source = try PluginSourceArgument(arguments) {
            guard arguments.optionalString("plugin") == nil, arguments.optionalString("version") == nil else {
                throw RPCFailure(-32602, "Give either a registry plugin or a path/url, not both")
            }
            let scope = PluginInstallScope(rawValue: arguments.optionalString("scope") ?? "user") ?? .user
            let mode: PluginInstallMode = arguments.bool("link") ? .link : .copy
            if mode == .link, case .link = source { throw RPCFailure(-32602, "link is for a plugin folder at path") }
            return requestAddedPluginInstall(source, scope: scope, mode: mode, author: author)
        }
        guard !arguments.bool("link") else { throw RPCFailure(-32602, "link is for a plugin folder at path") }
        guard let id = arguments.optionalString("plugin") else {
            throw RPCFailure(-32602, "Give a registry plugin ID, a path or a url")
        }
        guard arguments.optionalString("scope") == nil else {
            throw RPCFailure(-32602, "scope is only for path or url; registry plugins install for this Mac")
        }
        let version = arguments.optionalString("version")
        let job = jobs.start("plugins.install", author: author, detail: id, work: { [weak self] reporter in
            guard let self else { throw CancellationError() }
            reporter.detail("Downloading \(id)")
            try await plugins.requestInstall(id, version: version)
            ui.showPlugins = true
            return .object(["plugin": .string(id), "approval": .string("pending")])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = id + ": " + error.localizedDescription
        })
        return .object(["job": .string(job), "state": .string("running")])
    }

    /// `plugins install --path/--url`: checks (and downloads) the plugin as a job, then shows the approval only the user
    /// can give.
    private func requestAddedPluginInstall(
        _ source: PluginSourceArgument, scope: PluginInstallScope, mode: PluginInstallMode = .copy,
        replacing: InstalledPlugin? = nil, author: Author
    ) -> JSONValue {
        let name = source.name
        let job = jobs.start("plugins.install", author: author, detail: name, work: { [weak self] reporter in
            guard let self else { throw CancellationError() }
            let plugin: InstalledPlugin
            switch source {
            case .path(let url):
                reporter.detail("Checking \(name)")
                plugin = try await plugins.requestLocalInstall(from: url, scope: scope, mode: mode, replacing: replacing)
            case .link(let link):
                reporter.detail("Downloading \(name)")
                plugin = try await plugins.requestLinkInstall(link, scope: scope)
            }
            ui.showPlugins = true
            return .object([
                "plugin": .string(plugin.id), "version": .string(plugin.manifest.version),
                "scope": .string(scope.rawValue), "mode": .string(mode.rawValue), "approval": .string("pending"),
            ])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = name + ": " + error.localizedDescription
        })
        return .object(["job": .string(job), "state": .string("running")])
    }
}

/// A plugin outside the registry named by `path` or `url` (with `ref` and `sha256`), or nil when neither is given.
enum PluginSourceArgument {
    case path(URL)
    case link(PluginLink)

    init?(_ arguments: CommandArguments) throws {
        let path = arguments.optionalString("path"), url = arguments.optionalString("url")
        let ref = arguments.optionalString("ref"), sha256 = arguments.optionalString("sha256")
        switch (path, url) {
        case (nil, nil):
            guard ref == nil, sha256 == nil else { throw RPCFailure(-32602, "ref and sha256 are for url") }
            return nil
        case (let path?, nil):
            guard ref == nil, sha256 == nil else { throw RPCFailure(-32602, "ref and sha256 are for url") }
            self = .path(URL(fileURLWithPath: path))
        case (nil, let url?):
            do { self = .link(try PluginLink(parsing: url, ref: ref, sha256: sha256)) } catch {
                throw RPCFailure.from(error, fallbackCode: -32602)
            }
        default:
            throw RPCFailure(-32602, "Give either a path or a url, not both")
        }
    }

    var name: String {
        switch self {
        case .path(let url): url.lastPathComponent
        case .link(let link): link.url.absoluteString
        }
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
            "source": origin.map { .object(["url": .string($0.url), "resolved": $0.resolved.map(JSONValue.string) ?? .null]) }
                ?? .null,
        ])
    }
}
