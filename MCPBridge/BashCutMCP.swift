import BashCutAutomation
import BashCutProject
import Foundation
import MCP

/// MCP tools are generated from the command specs; JSON Schemas convert to MCP values through JSON.
private let tools: [Tool] = CommandCatalog.specs.map { spec in
    Tool(name: spec.mcpToolName, description: spec.summary, inputSchema: value(spec.inputSchema) ?? .object([:]))
}

private func value<T: Encodable>(_ encodable: T) -> Value? {
    (try? JSONEncoder().encode(encodable)).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
}

/// Installed plugin actions as tools (`bashcut_action_<id>`), read from the running app; none when it is not
/// running or has no plugins.
private func actionTools() -> [PluginActionTools.Tool] {
    guard let response = try? MCPBridgeClient.call(
        method: "plugins.actions", arguments: Data("{}".utf8), token: AutomationPaths.sessionToken()),
        let actions = try? JSONDecoder().decode(JSONValue.self, from: response.data)
    else { return [] }
    return PluginActionTools.tools(from: actions)
}

private func result(_ response: MCPBridgeResponse) throws -> CallTool.Result {
    let structured: Value? = response.isObject ? try JSONDecoder().decode(Value.self, from: response.data) : nil
    return try CallTool.Result(
        content: [.text(text: response.text, annotations: nil, _meta: nil)],
        structuredContent: structured, isError: false)
}

private func failure(_ message: String) -> CallTool.Result {
    .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}

@main enum BashCutMCP {
    static func main() async throws {
        let server = Server(
            name: "bashcut-mcp", version: "0.1.0",
            capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            let plugins = actionTools().map {
                Tool(name: $0.name, description: $0.description, inputSchema: value($0.inputSchema) ?? .object([:]))
            }
            return .init(tools: tools + plugins)
        }
        await server.withMethodHandler(CallTool.self) { request in
            DebugLog.write("mcp", "call \(request.name)")
            do {
                let arguments = try JSONEncoder().encode(request.arguments ?? [:])
                if request.name.hasPrefix(PluginActionTools.prefix) {
                    guard let action = actionTools().first(where: { $0.name == request.name }) else {
                        return failure("That plugin action is not installed or not available any more; see bashcut_plugins_actions")
                    }
                    let params = try JSONDecoder().decode(JSONValue.self, from: arguments)
                    let call = try JSONEncoder().encode(JSONValue.object(["action": .string(action.actionID), "params": params]))
                    return try result(MCPBridgeClient.call(
                        method: "plugins.run", arguments: call, token: AutomationPaths.sessionToken()))
                }
                guard let spec = CommandCatalog.specs.first(where: { $0.mcpToolName == request.name }) else {
                    DebugLog.write("mcp", "unknown tool \(request.name)")
                    return failure("Unknown BashCut tool")
                }
                return try result(MCPBridgeClient.call(
                    method: spec.name, arguments: arguments, token: AutomationPaths.sessionToken()))
            } catch {
                DebugLog.write("mcp", "\(request.name) FAILED: \(error.localizedDescription)")
                return failure(error.localizedDescription)
            }
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
