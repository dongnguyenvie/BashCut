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

/// Results go out as text only. The SDK re-decodes every result into a `Value` tree through Codable, which costs
/// about 1 ms per KB of structured content (a 7 KB `timeline get` took 37 ms); one string decodes at once.
/// `structuredContent` is optional for tools without an output schema, and clients read the text.
private func result(_ response: MCPBridgeResponse) -> CallTool.Result {
    CallTool.Result(content: [.text(text: response.text, annotations: nil, _meta: nil)], isError: false)
}

private func failure(_ message: String) -> CallTool.Result {
    .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}

/// `tools/list` answered before the SDK sees it. The SDK encoded the 35 KB tool list through its `Value` tree on
/// every call (about 35 ms); here the catalog is encoded once and only installed plugin actions are asked for
/// each time. The SDK handler below stays for the capability and as the fallback.
enum ToolList {
    static let catalog: Data = encode(CommandCatalog.specs.map { tool($0.mcpToolName, $0.summary, $0.inputSchema) })

    private static func tool(_ name: String, _ description: String, _ schema: JSONValue) -> JSONValue {
        .object(["name": .string(name), "description": .string(description), "inputSchema": schema])
    }

    private static func encode(_ tools: [JSONValue]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(tools)) ?? Data("[]".utf8)
    }

    /// The JSON-RPC response when `line` is a `tools/list` request, else nil.
    static func response(to line: Data) -> Data? {
        guard line.range(of: Data("\"tools/list\"".utf8)) != nil,
            let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            request["method"] as? String == "tools/list", let id = request["id"],
            let idJSON = try? JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed)
        else { return nil }
        var tools = catalog
        let plugins = actionTools().map { tool($0.name, $0.description, $0.inputSchema) }
        if !plugins.isEmpty {
            // Splices `[catalog…]` and `[plugins…]` into one array.
            tools.removeLast()
            tools.append(UInt8(ascii: ","))
            tools.append(encode(plugins).dropFirst())
        }
        var response = Data(#"{"jsonrpc":"2.0","id":"#.utf8)
        response.append(idJSON)
        response.append(Data(#","result":{"tools":"#.utf8))
        response.append(tools)
        response.append(Data("}}".utf8))
        return response
    }
}

@main enum BashCutMCP {
    static func main() async throws {
        defer { DebugLog.flush() }
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
            DebugLog.write("mcp", "tool call")
            do {
                let arguments = try JSONEncoder().encode(request.arguments ?? [:])
                if request.name.hasPrefix(PluginActionTools.prefix) {
                    guard let action = actionTools().first(where: { $0.name == request.name }) else {
                        return failure("That plugin action is not installed or not available any more; see bashcut_plugins_actions")
                    }
                    let params = try JSONDecoder().decode(JSONValue.self, from: arguments)
                    let call = try JSONEncoder().encode(JSONValue.object(["action": .string(action.actionID), "params": params]))
                    return result(try MCPBridgeClient.call(
                        method: "plugins.run", arguments: call, token: AutomationPaths.sessionToken()))
                }
                guard let spec = CommandCatalog.specs.first(where: { $0.mcpToolName == request.name }) else {
                    DebugLog.write("mcp", "unknown tool")
                    return failure("Unknown BashCut tool")
                }
                return result(try MCPBridgeClient.call(
                    method: spec.name, arguments: arguments, token: AutomationPaths.sessionToken()))
            } catch {
                DebugLog.write("mcp", "tool call failed")
                return failure(error.localizedDescription)
            }
        }
        Task.detached { _ = ToolList.catalog }
        let transport = BlockingStdioTransport(intercept: ToolList.response(to:))
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
