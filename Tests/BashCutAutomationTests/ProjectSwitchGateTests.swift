import BashCutAutomation
import BashCutProject
import Foundation
import Testing

@MainActor
struct ProjectSwitchGateTests {
    private func request(_ method: String, token: String, params: [String: JSONValue] = [:]) -> RPCRequest {
        RPCRequest(id: .string(UUID().uuidString), method: method, params: params, token: token)
    }

    @Test("After a project switch a token must read the project before it can edit again")
    func editsWaitForARead() async throws {
        let registry = CommandRegistry()
        registry.register("context.get") { _, _ in .object([:]) }
        registry.register("timeline.undo") { _, _ in .object(["undone": .bool(true)]) }
        let token = registry.issueToken(author: .codex)
        let other = registry.issueToken(author: .claude)
        let undo = request("timeline.undo", token: token, params: ["baseRev": .integer(3)])
        #expect(await registry.handle(undo).error == nil)

        registry.projectSwitched(to: "Sample video project")
        #expect(registry.needsProjectRead(token) && registry.needsProjectRead(other))
        let refused = await registry.handle(undo)
        #expect(refused.error?.message.contains("Sample video project") == true)

        #expect(await registry.handle(request("context.get", token: token)).error == nil)
        #expect(await registry.handle(undo).error == nil)
        #expect(registry.needsProjectRead(other))
        registry.revoke(other)
        #expect(!registry.needsProjectRead(other))
    }

    @Test("The token that switched the project already knows it")
    func switcherIsNotGated() async throws {
        let registry = CommandRegistry()
        registry.register("project.open") { _, _ in
            registry.projectSwitched(to: "Next")
            return .object(["rev": .integer(0)])
        }
        let token = registry.issueToken(author: .codex)
        let other = registry.issueToken(author: .claude)
        #expect(await registry.handle(request("project.open", token: token, params: ["path": .string("/p")])).error == nil)
        #expect(!registry.needsProjectRead(token))
        #expect(registry.needsProjectRead(other))
    }
}
