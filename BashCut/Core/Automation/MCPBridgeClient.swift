import BashCutProject
import Foundation

public struct MCPBridgeResponse: Sendable {
    public let data: Data
    /// What the MCP tool returns: string results as they are, everything else as compact JSON.
    public let text: String
}

public enum MCPBridgeClient {
    public static func call(
        method: String, arguments: Data, token: String?, path: String = AutomationPaths.socket
    ) throws -> MCPBridgeResponse {
        let params = try JSONDecoder().decode([String: JSONValue].self, from: arguments)
        let response = try UnixRPCClient.call(
            RPCRequest(method: method, params: params, token: token), path: path)
        let result = response.result ?? .null
        let encoder = JSONEncoder()
        // Compact: agents read every byte as tokens, and indentation added about a third more.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result)
        return MCPBridgeResponse(
            data: data,
            text: result.string ?? String(data: data, encoding: .utf8) ?? "null")
    }
}
