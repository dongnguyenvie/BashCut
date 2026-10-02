import BashCutAutomation
import BashCutProject
import Foundation
import OSLog

/// The automation endpoint of the running app: the command registry with its session tokens and
/// audit log, the Unix socket server the CLI and MCP bridge talk to, and the 0600 token file that
/// lets agents outside BashCut edit. Command handlers are registered by the document.
@MainActor
public final class AutomationController {
    public let registry: CommandRegistry
    /// Token written to `tokenFile` for agents outside the app; it outlives project switches, unlike
    /// in-app terminal tokens.
    public private(set) var externalAgentToken: String?
    private let server = UnixRPCServer()
    private let socket: String
    private let tokenFile: URL

    public init(
        auditURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BashCut/audit.jsonl"),
        socket: String = AutomationPaths.socket, tokenFile: URL = AutomationPaths.tokenFile
    ) {
        let audit = AuditStore(url: auditURL)
        registry = CommandRegistry { event in
            Task {
                do { try await audit.append(event) } catch {
                    Logger(subsystem: "app.bashcut", category: "automation").error("Audit write failed")
                }
            }
        }
        self.socket = socket
        self.tokenFile = tokenFile
    }

    /// Opens the socket; requests go through `registry`.
    public func start() async throws {
        try await server.start(path: socket) { [registry] in await registry.handle($0) }
    }

    public func stop() async {
        await server.stop()
    }

    /// On: issues a fresh `agent` token and writes it to the token file (0600, in a 0700 folder),
    /// revoking the previous one. Off: revokes it and removes the file.
    public func setExternalAgentAccess(_ enabled: Bool) {
        removeExternalAgentToken()
        guard enabled else {
            DebugLog.write("access", "external agent access off; token file removed")
            return
        }
        let token = registry.issueToken(author: .agent)
        do {
            let manager = FileManager.default
            let folder = tokenFile.deletingLastPathComponent()
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let staging = folder.appendingPathComponent(".automation-token-" + UUID().uuidString)
            guard manager.createFile(atPath: staging.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            _ = try manager.replaceItemAt(tokenFile, withItemAt: staging)
            externalAgentToken = token
            DebugLog.write("access", "external agent token written to \(tokenFile.path)")
        } catch {
            registry.revoke(token)
            DebugLog.write("access", "external agent token FAILED: \(error.localizedDescription)")
        }
    }

    /// Revokes the external-agent token and removes its file (Settings switch off, app quit).
    public func removeExternalAgentToken() {
        if let externalAgentToken { registry.revoke(externalAgentToken) }
        externalAgentToken = nil
        try? FileManager.default.removeItem(at: tokenFile)
    }
}
