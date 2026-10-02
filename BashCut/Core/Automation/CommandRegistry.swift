import BashCutProject
import Foundation

public struct AuditEvent: Codable, Sendable {
    public let date: Date
    public let method: String
    public let author: Author?
    public let succeeded: Bool
}

@MainActor public final class CommandRegistry {
    public typealias Handler = @MainActor (CommandArguments, Author?) async throws -> JSONValue
    private var handlers: [String: Handler] = [:]
    private var tokens: [String: Author] = [:]
    private let audit: @Sendable (AuditEvent) -> Void
    public init(audit: @escaping @Sendable (AuditEvent) -> Void = { _ in }) { self.audit = audit }

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
    public func revoke(_ token: String) { tokens.removeValue(forKey: token) }
    public func revokeAll() { tokens.removeAll() }
    public func recordApproval(method: String, author: Author, approved: Bool) {
        audit(
            AuditEvent(
                date: Date(), method: method + (approved ? ".approved" : ".denied"),
                author: author, succeeded: approved))
    }
    public func handle(_ request: RPCRequest) async -> RPCResponse {
        let author = request.token.flatMap { tokens[$0] }
        do {
            guard request.jsonrpc == "2.0" else { throw RPCFailure(-32600, "JSON-RPC 2.0 required") }
            guard let spec = CommandCatalog.spec(named: request.method), let handler = handlers[request.method]
            else {
                throw RPCFailure(-32601, "Unknown command: \(request.method)")
            }
            if spec.mode == .edit || spec.mode == .privileged {
                guard author != nil else {
                    throw RPCFailure(-32001, "A live agent session token is required")
                }
            }
            let arguments = CommandArguments(try spec.validate(request.params))
            let result = try await handler(arguments, author)
            audit(AuditEvent(date: Date(), method: request.method, author: author, succeeded: true))
            return RPCResponse(id: request.id, result: result)
        } catch {
            audit(AuditEvent(date: Date(), method: request.method, author: author, succeeded: false))
            let failure: RPCFailure
            if let wire = error as? RPCFailure {
                failure = wire
            } else if case ProjectError.staleRevision = error {
                failure = RPCFailure(-32002, error.localizedDescription)
            } else {
                failure = RPCFailure(-32602, error.localizedDescription)
            }
            return RPCResponse(id: request.id, error: failure)
        }
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
