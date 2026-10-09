import BashCutProject
import Foundation

/// App commands a plugin's view or action requests may call over the session host channel (plugin API 8, #399): the
/// chat-agent boundary plus running plugin actions and status messages. They run as author `plugin` with one token
/// per plugin, so edits are validated, undoable and attributed like any command. `plugins.invoke` is answered by the
/// caller before it gets here, since it needs the calling plugin's `uses`.
@MainActor public final class PluginCommandSession {
    public static let allowedMethods: Set<String> = ChatCommandSession.allowedMethods.union([
        "plugins.run", "plugins.invoke", "plugins.show-view",
    ]).subtracting(["plugins.view", "plugins.view-event"])
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
            method != "plugins.invoke"
        else {
            return RPCResponse(id: id, error: RPCFailure(-32601, "Plugins cannot run \(method)").typed)
        }
        if token == nil { token = registry.issueToken(author: .plugin) }
        return await registry.handle(RPCRequest(id: id, method: method, params: params, token: token))
    }
}
