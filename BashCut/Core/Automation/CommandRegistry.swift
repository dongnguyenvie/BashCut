import BashCutProject
import Foundation

public struct AuditEvent: Codable, Sendable {
    public let date: Date
    public let method: String
    public let author: Author?
    public let succeeded: Bool
}

/// The live session token of the command running on this task, so checks deeper in the app (the scope guard,
/// #356) know which agent session made an edit. Nil outside a command or for a request without a live token.
public enum CommandCaller {
    @TaskLocal public static var token: String?
}

@MainActor public final class CommandRegistry {
    public typealias Handler = @MainActor (CommandArguments, Author?) async throws -> JSONValue
    private var handlers: [String: Handler] = [:]
    private var tokens: [String: Author] = [:]
    /// Tokens that have not read the project since it was switched, with the new project's name.
    private var switchedProject: [String: String] = [:]
    /// Reads that show an agent the open project; any one of them ends the gate after a switch.
    static let projectReads: Set<String> = ["context.get", "timeline.get", "project.get"]
    /// Commands that switch the project; their result shows the new project to the caller.
    static let projectSwitches: Set<String> = ["project.open", "project.create", "project.close", "edl.import"]
    private let audit: @Sendable (AuditEvent) -> Void
    private let logger: (@Sendable (String, String) -> Void)?
    public init(audit: @escaping @Sendable (AuditEvent) -> Void = { _ in }) {
        logger = nil
        self.audit = audit
    }

    init(logger: @escaping @Sendable (String, String) -> Void) {
        self.logger = logger
        audit = { _ in }
    }

    private func log(_ category: String, _ message: @autoclosure () -> String) {
        if let logger { logger(category, message()) } else { DebugLog.write(category, message()) }
    }

    /// Registers the handler for a catalogued command. Requests reach it only after spec validation.
    public func register(_ method: String, handler: @escaping Handler) {
        assert(CommandCatalog.spec(named: method) != nil, "\(method) is not in CommandCatalog.specs")
        handlers[method] = handler
    }

    /// Catalogued commands that have no handler yet.
    public var unhandledCommands: [String] { CommandCatalog.specs.map(\.name).filter { handlers[$0] == nil } }

    public func issueToken(author: Author) -> String {
        let token = UUID().uuidString + UUID().uuidString
        tokens[token] = author
        return token
    }
    public func revoke(_ token: String) {
        tokens.removeValue(forKey: token)
        switchedProject.removeValue(forKey: token)
    }

    /// After the open project changes, every live token must read the new project (`context get`, `timeline get` or
    /// `project get`) before it may edit, so an agent cannot apply what it remembers of the old project to the new
    /// one. Sessions stay open across a switch; this is the boundary instead.
    public func projectSwitched(to name: String) {
        for token in tokens.keys { switchedProject[token] = name }
    }

    /// Whether `token` still has to read the project after a switch.
    public func needsProjectRead(_ token: String) -> Bool { switchedProject[token] != nil }
    /// The author a live token edits as, or nil for an unknown or revoked token.
    public func author(for token: String) -> Author? { tokens[token] }
    public func revokeAll() {
        tokens.removeAll()
        switchedProject.removeAll()
    }
    /// `automatic` marks requests run without a prompt because the user turned confirmation off.
    public func recordApproval(method: String, author: Author, approved: Bool, automatic: Bool = false) {
        audit(
            AuditEvent(
                date: Date(), method: method + (automatic ? ".auto-approved" : approved ? ".approved" : ".denied"),
                author: author, succeeded: approved))
    }
    /// Audits work that does not arrive as a command, such as plugin actions and hooks.
    public func record(method: String, author: Author?, succeeded: Bool) {
        audit(AuditEvent(date: Date(), method: method, author: author, succeeded: succeeded))
    }

    public func handle(_ request: RPCRequest) async -> RPCResponse {
        let author = request.token.flatMap { tokens[$0] }
        let started = Date()
        let who = author.map { "\($0)" } ?? "anonymous"
        do {
            guard request.jsonrpc == "2.0" else { throw RPCFailure(-32600, "JSON-RPC 2.0 required") }
            guard let spec = CommandCatalog.spec(named: request.method), let handler = handlers[request.method]
            else {
                throw RPCFailure(-32601, "Unknown command: \(request.method)")
            }
            if spec.mode != .read {
                guard author != nil else {
                    throw RPCFailure(-32001, "A live agent session token is required")
                }
                if let token = request.token, let name = switchedProject[token] {
                    throw RPCFailure(
                        -32002, "The open project changed to \"\(name)\". Read it first (context get or timeline get), "
                            + "then retry with its revision.")
                }
            }
            if Self.projectReads.contains(request.method), let token = request.token {
                switchedProject.removeValue(forKey: token)
            }
            let arguments = CommandArguments(try spec.validate(request.params))
            let result = try await CommandCaller.$token.withValue(author == nil ? nil : request.token) {
                try await handler(arguments, author)
            }
            if Self.projectSwitches.contains(request.method), let token = request.token {
                switchedProject.removeValue(forKey: token)
            }
            audit(AuditEvent(date: Date(), method: request.method, author: author, succeeded: true))
            log(
                "rpc", "\(request.method) by \(who) ok in \(Self.milliseconds(since: started)) ms "
                    + "params=\(Self.summary(spec.logParameters(arguments.values)))")
            return RPCResponse(id: request.id, result: result)
        } catch {
            audit(AuditEvent(date: Date(), method: request.method, author: author, succeeded: false))
            let failure = RPCFailure.from(error, fallbackCode: -32602)
            log(
                "rpc", "\(CommandCatalog.spec(named: request.method)?.name ?? "unknown command") by \(who) "
                    + "FAILED \(failure.code) in \(Self.milliseconds(since: started)) ms")
            return RPCResponse(id: request.id, error: failure)
        }
    }

    private static func milliseconds(since date: Date) -> Int { Int(Date().timeIntervalSince(date) * 1000) }

    /// Compact JSON for the debug log, at most `limit` characters. It stops walking as soon as the limit is reached,
    /// so a large result (project.get, timeline.get) costs no more than a small one on the main actor.
    nonisolated static func summary(_ params: [String: JSONValue], limit: Int = 400) -> String {
        summary(.object(params), limit: limit)
    }

    nonisolated static func summary(_ value: JSONValue, limit: Int = 400) -> String {
        var writer = BoundedJSONWriter(limit: limit)
        return writer.write(value) ? writer.text : String(writer.text.prefix(limit)) + "…"
    }
}

/// Writes JSON until `limit` bytes; each call returns false once the limit is reached.
private struct BoundedJSONWriter {
    let limit: Int
    var text = ""

    mutating func write(_ value: JSONValue) -> Bool {
        switch value {
        case .null: append("null")
        case .bool(let flag): append(flag ? "true" : "false")
        case .integer(let number): append(String(number))
        case .number(let number): append(String(number))
        case .string(let string): append(quoted(string))
        case .array(let values): write(values.lazy.map { (nil, $0) }, open: "[", close: "]")
        case .object(let fields): write(fields.keys.sorted().lazy.map { ($0, fields[$0] ?? .null) }, open: "{", close: "}")
        }
    }

    private mutating func write(_ entries: some Sequence<(String?, JSONValue)>, open: String, close: String) -> Bool {
        guard append(open) else { return false }
        var first = true
        for (key, value) in entries {
            if !first, !append(",") { return false }
            first = false
            if let key, !append(quoted(key) + ":") { return false }
            if !write(value) { return false }
        }
        return append(close)
    }

    private mutating func append(_ piece: String) -> Bool {
        text += piece
        return text.utf8.count < limit
    }

    private func quoted(_ string: String) -> String {
        let escaped = string.prefix(limit).replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return "\"" + escaped + "\""
    }
}

public actor AuditStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func append(_ event: AuditEvent) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONEncoder().encode(event)
        data.append(10)
        try handle.write(contentsOf: data)
    }
}
