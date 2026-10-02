import BashCutAutomation
import Foundation
import MCP

/// MCP tools are generated from the command specs; JSON Schemas convert to MCP values through JSON.
private let tools: [Tool] = CommandCatalog.specs.map { spec in
    let schema = (try? JSONEncoder().encode(spec.inputSchema)).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    return Tool(name: spec.mcpToolName, description: spec.summary, inputSchema: schema ?? .object([:]))
}

@main enum BashCutMCP {
    static func main() async throws {
        let server = Server(
            name: "bashcut-mcp", version: "0.1.0",
            capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { request in
            DebugLog.write("mcp", "call \(request.name)")
            guard let spec = CommandCatalog.specs.first(where: { $0.mcpToolName == request.name }) else {
                DebugLog.write("mcp", "unknown tool \(request.name)")
                return .init(content: [.text(text: "Unknown BashCut tool", annotations: nil, _meta: nil)], isError: true)
            }
            do {
                let arguments = try JSONEncoder().encode(request.arguments ?? [:])
                let response = try MCPBridgeClient.call(
                    method: spec.name, arguments: arguments,
                    token: AutomationPaths.sessionToken())
                let structured = try JSONDecoder().decode(Value.self, from: response.data)
                return CallTool.Result(
                    content: [.text(text: response.text, annotations: nil, _meta: nil)],
                    structuredContent: Optional.some(structured), isError: false)
            } catch {
                DebugLog.write("mcp", "\(request.name) FAILED: \(error.localizedDescription)")
                return .init(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true)
            }
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
