import BashCutProject
import Foundation

public struct RPCRequest: Codable, Sendable {
    public var jsonrpc = "2.0"
    public let id: JSONValue
    public let method: String
    public var params: [String: JSONValue]
    public let token: String?
    public init(
        id: JSONValue = .integer(1), method: String, params: [String: JSONValue] = [:],
        token: String? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.token = token
    }
}
public struct RPCFailure: Error, Codable, Sendable, LocalizedError {
    public let code: Int
    public let message: String
    public init(_ code: Int, _ message: String) {
        self.code = code
        self.message = message
    }
    public var errorDescription: String? { message }
}
public struct RPCResponse: Codable, Sendable {
    public var jsonrpc = "2.0"
    public let id: JSONValue
    public let result: JSONValue?
    public let error: RPCFailure?
    public init(id: JSONValue, result: JSONValue? = nil, error: RPCFailure? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum CommandMode: String, Sendable { case read, ui, edit, privileged }
/// Agent operations use the core `EditOperation` codec; internal operations
/// (`group`, `restore`) are rejected at this boundary.
public enum WireOperations {
    public static func decode(_ value: JSONValue) throws -> [EditOperation] {
        guard case .array(let array) = value, !array.isEmpty, array.count <= 1000 else {
            throw RPCFailure(-32602, "ops must be a nonempty array of at most 1000 operations")
        }
        return try array.map { operation in
            do {
                return try EditOperation(json: operation)
            } catch let error as ProjectError {
                throw RPCFailure(-32602, error.localizedDescription)
            }
        }
    }
}
