import Foundation
import BashCutProject
import Testing

@testable import BashCutAutomation

struct RPCFailureTests {
    @Test("CLI exit statuses distinguish stale, busy, permissions, usage, transport and internal errors")
    func statuses() {
        for (code, status): (Int, Int32) in [(-32002, 75), (-32003, 69), (-32001, 77), (-32004, 77), (-32602, 64),
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
        let data = stale.error?.data?.object ?? [:]
        #expect(data["expected"] == .integer(1) && data["actual"] == .integer(2))
        #expect(data["category"] == .string("stale_revision") && data["retryable"] == .bool(true))
        #expect(data["remediation"]?.object["command"] == .string("context.get"))
    }

    @Test("Every error gets a category and retryable from its code; a thrower's category and data win")
    func typed() {
        let invalid = RPCFailure(-32602, "Missing media").typed.data?.object ?? [:]
        #expect(invalid["category"] == .string("invalid_arguments") && invalid["retryable"] == .bool(false))
        #expect(invalid["remediation"] == nil)
        let dialog = RPCFailure(-32003, "Answer the open dialog", category: .busyDialog).typed
        #expect(dialog.code == -32003 && dialog.category == .busyDialog)
        #expect(dialog.data?.object["remediation"]?.object["command"] == .string("ui.dialog"))
        let approval = RPCFailure(-32003, "Another privileged action is awaiting approval", category: .busyApproval).typed
        #expect(approval.data?.object["retryable"] == .bool(true) && approval.category != dialog.category)
        let own = RPCFailure(-32603, "x", data: .object(["retryable": .bool(true)])).typed.data?.object ?? [:]
        #expect(own["retryable"] == .bool(true) && own["category"] == .string("internal"))
        #expect(RPCFailure(-32603, "x", data: .string("raw")).typed.data?.object["detail"] == .string("raw"))
        #expect(RPCFailure(-32000, "Cannot reach BashCut").typed.payload.object["error"]?.object["data"]?
            .object["category"] == .string("unavailable"))
    }

    @Test("A project error is invalid arguments, but a stale revision keeps -32002 and its revisions")
    func projectErrors() {
        #expect(RPCFailure.invalid(.invalid("bad")).code == -32602)
        let stale = RPCFailure.invalid(.staleRevision(expected: 1, actual: 15))
        #expect(stale.code == -32002 && stale.data?.object["actual"] == .integer(15))
    }

    @Test("A file conflict is busy -32003 with category file_conflict, also through a generic catch")
    func fileConflict() {
        let failure = RPCFailure.from(FileConflictError("Resolve the file conflict before editing."), fallbackCode: -32602).typed
        #expect(failure.code == -32003 && failure.category == .fileConflict)
        #expect(failure.data?.object["retryable"] == .bool(true))
        #expect(failure.data?.object["remediation"]?.object["command"] == .string("context.get"))
    }

    @Test("Recent failures are kept per session token, newest first, with the repeated run at the newest end")
    @MainActor func recentFailures() async {
        let registry = CommandRegistry()
        registry.register("timeline.undo") { _, _ in throw RPCFailure(-32003, "busy", category: .busyRunning) }
        registry.register("timeline.redo") { _, _ in throw ProjectError.staleRevision(expected: 1, actual: 2) }
        let mine = registry.issueToken(author: .codex), other = registry.issueToken(author: .claude)
        for method in ["timeline.redo", "timeline.undo", "timeline.undo", "timeline.undo"] {
            _ = await registry.handle(RPCRequest(method: method, params: ["baseRev": .integer(1)], token: mine))
        }
        _ = await registry.handle(RPCRequest(method: "timeline.redo", params: ["baseRev": .integer(1)], token: other))
        let json = registry.recentFailures(token: mine).object
        #expect(json["count"] == .integer(4) && json["repeated"] == .integer(3))
        let items = json["items"]?.array ?? []
        #expect(items.first?.object["category"] == .string("busy_running"))
        #expect(items.last?.object["method"] == .string("timeline.redo"))
        #expect(registry.recentFailures(token: nil).object["count"] == .integer(5))
        #expect(registry.recentFailures(token: mine, now: Date().addingTimeInterval(3_600)).object["count"] == .integer(0))
    }
}

struct CommandCallerTests {
    @Test("Handlers see the live token they run with, and nil for a request without one")
    @MainActor func token() async {
        let registry = CommandRegistry()
        var seen: [String?] = []
        registry.register("timeline.undo") { _, _ in
            seen.append(CommandCaller.token)
            return .null
        }
        registry.register("context.get") { _, _ in
            seen.append(CommandCaller.token)
            return .null
        }
        let token = registry.issueToken(author: .agent)
        _ = await registry.handle(RPCRequest(method: "timeline.undo", params: ["baseRev": .integer(1)], token: token))
        _ = await registry.handle(RPCRequest(method: "context.get", token: "revoked"))
        _ = await registry.handle(RPCRequest(method: "context.get"))
        #expect(seen == [token, nil, nil])
        #expect(CommandCaller.token == nil)
    }

    @Test("jobs.wait gets a socket read timeout past its wait; other calls get 30 s")
    func waitTimeout() {
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "jobs.status")) == 30)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "jobs.wait", params: ["timeout": .integer(5)])) == 15)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "jobs.wait")) == JobWaitDefaults.seconds + 10)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "jobs.wait", params: ["timeout": .integer(999)])) == JobWaitDefaults.maximum + 10)
        // Calls that wait for their own work get the time it may take; without the option they get the 30 s default.
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "review.run", params: ["measure": .bool(true)])) == 115)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "export.start", params: ["wait": .bool(true)])) == 115)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "project.create", params: ["importFootage": .bool(true)])) == 120)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "project.create")) == 30)
        #expect(UnixRPCClient.readSeconds(RPCRequest(method: "review.verify", params: ["id": .string("all")])) == 115)
    }

    @Test("jobs.wait takes a timeout past its maximum (the wait is cut to it) instead of refusing the call")
    func longWait() throws {
        let invocation = try CommandLineParser.parse(["jobs", "wait", "J1", "--timeout", "500", "--done"])
        #expect(invocation.params["timeout"] == .integer(500))
    }
}

/// Socket lines parsed with `JSONValue(parsing:)` give what the `Decodable` forms gave.
struct RPCParseTests {
    @Test("Requests and responses parse to the same values as JSONDecoder, and malformed lines fail")
    func sameAsDecodable() throws {
        let request = RPCRequest(
            id: .integer(7), method: "timeline.apply",
            params: ["ops": .array([.object(["at": .integer(30), "gain": .number(0.5), "on": .bool(true)])]), "x": .null],
            token: "t")
        let line = try JSONEncoder().encode(request)
        let parsed = try RPCRequest.parse(line)
        let decoded = try JSONDecoder().decode(RPCRequest.self, from: line)
        #expect(parsed.id == decoded.id && parsed.method == decoded.method && parsed.params == decoded.params)
        #expect(parsed.token == "t" && decoded.token == "t")
        let noToken = try RPCRequest.parse(Data(#"{"jsonrpc":"2.0","id":"a","method":"m","params":{"n":1.0}}"#.utf8))
        #expect(noToken.token == nil && noToken.params["n"] == .integer(1) && noToken.id == .string("a"))
        for bad in [#"{"jsonrpc":"2.0","id":1,"method":"m"}"#, "not json", #"{"jsonrpc":"2.0","id":1,"method":"m","params":{},"token":3}"#] {
            #expect(throws: RPCFailure.self) { try RPCRequest.parse(Data(bad.utf8)) }
        }

        let failure = RPCFailure(-32004, "Blocked", data: .object(["outOfScope": .array([.string("w")])]))
        for response in [
            RPCResponse(id: .integer(1), result: .object(["rev": .integer(3), "share": .number(0.25)])),
            RPCResponse(id: .integer(2), error: failure), RPCResponse(id: .null),
        ] {
            let line = try JSONEncoder().encode(response)
            let parsed = try RPCResponse.parse(line)
            let decoded = try JSONDecoder().decode(RPCResponse.self, from: line)
            #expect(parsed.id == decoded.id && parsed.result == decoded.result)
            #expect(parsed.error?.code == decoded.error?.code && parsed.error?.message == decoded.error?.message)
            #expect(parsed.error?.data == decoded.error?.data)
        }
        #expect((try? RPCResponse.parse(Data("{".utf8))) == nil)
        #expect(throws: RPCFailure.self) { try RPCResponse.parse(Data(#"{"id":1}"#.utf8)) }
    }

    @Test("Parsing a large answer is faster than Decodable", .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"))
    func speed() throws {
        let items = (0..<20_000).map { index in
            JSONValue.object(["id": .string("v\(index)"), "at": .integer(index * 30), "gain": .number(0.5), "on": .bool(true)])
        }
        let line = try JSONEncoder().encode(RPCResponse(id: .integer(1), result: .object(["items": .array(items)])))
        func time(_ body: () throws -> Void) rethrows -> Double {
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                try body()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            return samples.sorted()[2]
        }
        let decodable = try time { _ = try JSONDecoder().decode(RPCResponse.self, from: line) }
        let parsing = try time { _ = try RPCResponse.parse(line) }
        print("RPC response \(line.count / 1_000) KB: Decodable \(decodable) ms, parse \(parsing) ms")
        #expect(parsing < decodable)
    }
}
