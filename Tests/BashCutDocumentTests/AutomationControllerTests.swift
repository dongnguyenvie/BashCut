import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation
import Testing

@MainActor
struct AutomationControllerTests {
    /// A short folder: socket paths must fit Darwin's sockaddr_un limit.
    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/bashcut-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func controller(in folder: URL) -> AutomationController {
        AutomationController(
            auditURL: folder.appendingPathComponent("audit.jsonl"),
            socket: folder.appendingPathComponent("a.sock").path,
            tokenFile: folder.appendingPathComponent("tokens/automation-token"))
    }

    @Test("External agent access writes a 0600 token file for the agent author and revokes it when off")
    func externalToken() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let automation = controller(in: root)
        let file = root.appendingPathComponent("tokens/automation-token")

        automation.setExternalAgentAccess(true)
        let first = try #require(automation.externalAgentToken)
        #expect(try String(contentsOf: file, encoding: .utf8) == first)
        let permissions = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        #expect(permissions & 0o777 == 0o600)
        #expect(automation.registry.author(for: first) == .agent)

        automation.setExternalAgentAccess(true)
        let second = try #require(automation.externalAgentToken)
        #expect(second != first)
        #expect(automation.registry.author(for: first) == nil)

        automation.setExternalAgentAccess(false)
        #expect(automation.externalAgentToken == nil)
        #expect(automation.registry.author(for: second) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Requests on the socket reach the registry")
    func socketRequests() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let automation = controller(in: root)
        automation.registry.register("context.get") { _, author in .string(author.map(\.rawValue) ?? "none") }
        automation.setExternalAgentAccess(true)
        let token = automation.externalAgentToken
        try await automation.start()
        let path = root.appendingPathComponent("a.sock").path
        let response = try await Task.detached {
            try UnixRPCClient.call(RPCRequest(method: "context.get", token: token), path: path)
        }.value
        await automation.stop()
        #expect(response.result == .string("agent"))
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
