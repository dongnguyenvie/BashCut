import BashCutProject
import Foundation

public struct MCPBridgeResponse: Sendable {
    public let data: Data
    public let text: String
    /// MCP `structuredContent` must be a JSON object; arrays, strings and other results travel only as text.
    public let isObject: Bool
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result)
        return MCPBridgeResponse(
            data: data,
            text: result.string ?? String(data: data, encoding: .utf8) ?? "null",
            isObject: { if case .object = result { true } else { false } }())
    }
}
