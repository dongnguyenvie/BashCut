import BashCutProject
import Testing

@testable import BashCutAutomation

struct RPCFailureTests {
    @Test("CLI exit statuses distinguish stale, busy, permissions, usage, transport and internal errors")
    func statuses() {
        for (code, status): (Int, Int32) in [(-32002, 75), (-32003, 69), (-32001, 77), (-32602, 64),
                                           (-32000, 69), (-32700, 65), (-32603, 70)] {
            #expect(RPCFailure(code, "error").exitStatus == status)
        }
    }

    @Test("Registry preserves typed busy failures and structured stale revisions")
    @MainActor func registry() async {
        struct Busy: RPCFailureProviding { var rpcFailure: RPCFailure { RPCFailure(-32003, "busy") } }
        let registry = CommandRegistry()
        registry.register("timeline.undo") { _, _ in throw Busy() }
        registry.register("timeline.redo") { _, _ in throw ProjectError.staleRevision(expected: 1, actual: 2) }
        let token = registry.issueToken(author: .codex)
        let busy = await registry.handle(RPCRequest(method: "timeline.undo", params: ["baseRev": .integer(1)], token: token))
        #expect(busy.error?.code == -32003)
        let stale = await registry.handle(RPCRequest(method: "timeline.redo", params: ["baseRev": .integer(1)], token: token))
        #expect(stale.error?.code == -32002)
        #expect(stale.error?.data == .object(["expected": .integer(1), "actual": .integer(2)]))
    }
}
