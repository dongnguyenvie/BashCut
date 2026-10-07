import BashCutProject
import Foundation

/// What kind of failure an RPC error is (P2-G2), in `error.data.category`. Busy failures share code -32003 and differ
/// here: a dialog to answer, a user approval still pending, work already running, or something not possible now.
public enum RPCErrorCategory: String, Sendable, CaseIterable {
    case malformed
    case invalidRequest = "invalid_request"
    case unknownCommand = "unknown_command"
    case invalidArguments = "invalid_arguments"
    case permission
    case staleRevision = "stale_revision"
    case outOfScope = "out_of_scope"
    case unavailable
    case busyDialog = "busy_dialog"
    case busyApproval = "busy_approval"
    case busyRunning = "busy_running"
    case notAvailableNow = "not_available_now"
    case fileConflict = "file_conflict"
    case capabilityMissing = "capability_missing"
    case unsupportedMedia = "unsupported_media"
    case internalError = "internal"

    /// Whether the same request can succeed later without changing it.
    public var retryable: Bool {
        switch self {
        case .staleRevision, .unavailable, .busyDialog, .busyApproval, .busyRunning, .fileConflict: true
        default: false
        }
    }

    /// The category an error code means when the thrower did not name one.
    static func of(code: Int) -> RPCErrorCategory {
        switch code {
        case -32700: .malformed
        case -32600: .invalidRequest
        case -32601: .unknownCommand
        case -32602: .invalidArguments
        case -32001: .permission
        case -32002: .staleRevision
        case -32003: .busyRunning
        case -32004: .outOfScope
        case -32000: .unavailable
        default: .internalError
        }
    }

    /// The command that reads the facts behind the category, when there is one. What to do next is the agent's
    /// (the categories are documented in the agent instructions), so there is no advice prose here.
    var remediation: JSONValue? {
        let command: String? = switch self {
        case .staleRevision, .fileConflict, .outOfScope: "context.get"
        case .busyDialog: "ui.dialog"
        case .busyRunning: "jobs.status"
        case .capabilityMissing: "capabilities.get"
        case .unsupportedMedia: "media.inventory"
        default: nil
        }
        return command.map { .object(["command": .string($0)]) }
    }
}

extension RPCFailure {
    /// A failure with its category set by the thrower (busy failures, missing capabilities).
    public init(_ code: Int, _ message: String, category: RPCErrorCategory, data: [String: JSONValue] = [:]) {
        var fields = data
        fields["category"] = .string(category.rawValue)
        self.init(code, message, data: .object(fields))
    }

    public var category: RPCErrorCategory {
        data?.object["category"]?.string.flatMap(RPCErrorCategory.init(rawValue:)) ?? .of(code: code)
    }

    /// The same failure with `category`, `retryable` and, where one exists, `remediation` in its data; what the
    /// thrower already put there wins. Other data stays (a non-object value moves to `detail`).
    public var typed: RPCFailure {
        var fields: [String: JSONValue]
        switch data {
        case .object(let object)?: fields = object
        case nil, .null?: fields = [:]
        case let other?: fields = ["detail": other]
        }
        let category = self.category
        fields["category"] = fields["category"] ?? .string(category.rawValue)
        fields["retryable"] = fields["retryable"] ?? .bool(category.retryable)
        if fields["remediation"] == nil, let remediation = category.remediation { fields["remediation"] = remediation }
        return RPCFailure(code, message, data: .object(fields))
    }
}

/// The project file changed on disk and the user has not resolved the conflict yet: edits and saves wait for it.
public struct FileConflictError: LocalizedError, RPCFailureProviding {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var rpcFailure: RPCFailure { RPCFailure(-32003, message, category: .fileConflict) }
}
