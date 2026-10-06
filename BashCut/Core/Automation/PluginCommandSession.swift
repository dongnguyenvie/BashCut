import BashCutProject
import Foundation

/// App commands a plugin's view or action requests may call over the session host channel (plugin API 8, #399): the
/// chat-agent boundary plus running plugin actions and status messages. They run as author `plugin` with one token
/// per plugin, so edits are validated, undoable and attributed like any command. `plugins.invoke` is answered by the
/// caller before it gets here, since it needs the calling plugin's `uses`.
@MainActor public final class PluginCommandSession {
    public static let allowedMethods: Set<String> = ChatCommandSession.allowedMethods.union([
        "plugins.run", "plugins.invoke", "plugins.views", "ui.notify",
    ]).subtracting(["plugins.view", "plugins.view-event"])
    private var token: String?

    public init() {}

    public func revoke(in registry: CommandRegistry) {
        if let token { registry.revoke(token) }
        token = nil
    }

    public func perform(_ method: String, params: [String: JSONValue], registry: CommandRegistry) async -> RPCResponse {
        let id = JSONValue.string(UUID().uuidString)
        guard Self.allowedMethods.contains(method), method != "plugins.invoke" else {
            return RPCResponse(id: id, error: RPCFailure(-32601, "Plugins cannot run \(method)"))
        }
        if token == nil { token = registry.issueToken(author: .plugin) }
        return await registry.handle(RPCRequest(id: id, method: method, params: params, token: token))
    }
}
