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
public protocol RPCFailureProviding: Error {
    var rpcFailure: RPCFailure { get }
}

public struct RPCFailure: Error, Codable, Sendable, LocalizedError {
    public let code: Int
    public let message: String
    public let data: JSONValue?
    public init(_ code: Int, _ message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
    public var errorDescription: String? { message }
    public static func from(_ error: any Error, fallbackCode: Int = -32603) -> RPCFailure {
        if let failure = error as? RPCFailure { return failure }
        if let provider = error as? any RPCFailureProviding { return provider.rpcFailure }
        if case ProjectError.staleRevision(let expected, let actual) = error {
            return RPCFailure(-32002, error.localizedDescription, data: .object([
                "expected": .integer(expected), "actual": .integer(actual)
            ]))
        }
        return RPCFailure(error is DecodingError ? -32700 : fallbackCode, error.localizedDescription)
    }
    /// sysexits-compatible process statuses; the original RPC code remains in the JSON error.
    public var exitStatus: Int32 {
        switch code {
        case -32002: 75 // stale revision: temporary failure
        case -32000, -32003: 69 // transport unavailable or editor busy
        case -32001: 77 // permission denied
        case -32600, -32601, -32602: 64 // invalid request or arguments
        case -32700: 65 // malformed response data
        default: 70 // internal error
        }
    }
    public var payload: JSONValue {
        var fields: [String: JSONValue] = ["code": .integer(code), "message": .string(message)]
        if let data { fields["data"] = data }
        return .object(["error": .object(fields)])
    }
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
