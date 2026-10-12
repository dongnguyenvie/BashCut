import BashCutProject
import Foundation

/// App commands a plugin's view or action requests may call over the session host channel (plugin API 8, #399): the
/// chat-agent boundary plus running plugin actions and status messages. They run as author `plugin` with one token
/// per plugin, so edits are validated, undoable and attributed like any command. `plugins.invoke` and `plugins.option`
/// are answered by the caller before they get here, since they need the calling plugin's manifest.
@MainActor public final class PluginCommandSession {
    public static let allowedMethods: Set<String> = ChatCommandSession.allowedMethods.union([
        "plugins.run", "plugins.invoke", "plugins.show-view", "plugins.option", "plugins.set-overlays",
        "plugins.overlays",
    ]).subtracting(["plugins.view", "plugins.view-event"])
    /// Host calls a plugin may make only about itself: `params.plugin` must be the caller's id.
    public nonisolated static let ownPluginMethods: Set<String> = [
        "plugins.show-view", "plugins.option", "plugins.set-overlays",
    ]
    /// Host calls the caller answers itself (they need the calling plugin's manifest).
    static let answeredByCaller: Set<String> = ["plugins.invoke", "plugins.option"]

    /// Why the plugin `caller` may not make this call about another plugin, or nil when it may.
    public nonisolated static func ownPluginRefusal(_ method: String, params: [String: JSONValue], caller: String) -> String? {
        guard ownPluginMethods.contains(method), params["plugin"]?.string != caller else { return nil }
        switch method {
        case "plugins.option": return "A plugin can only set its own options"
        case "plugins.set-overlays": return "A plugin can only set its own overlays"
        default: return "A plugin can only show its own views"
        }
    }

    /// The chat agent's `ui.action` actions plus status messages (`ui.action notify`).
    public static let allowedUIActions = ChatCommandSession.allowedUIActions.union(["notify"])
    private var token: String?

    public init() {}

    public func revoke(in registry: CommandRegistry) {
        if let token { registry.revoke(token) }
        token = nil
    }

    public func perform(_ method: String, params: [String: JSONValue], registry: CommandRegistry) async -> RPCResponse {
        let id = JSONValue.string(UUID().uuidString)
        guard ChatCommandSession.allows(method, params: params, methods: Self.allowedMethods, actions: Self.allowedUIActions),
            !Self.answeredByCaller.contains(method)
        else {
            return RPCResponse(id: id, error: RPCFailure(-32601, "Plugins cannot run \(method)").typed)
        }
        if token == nil { token = registry.issueToken(author: .plugin) }
        return await registry.handle(RPCRequest(id: id, method: method, params: params, token: token))
    }
}
