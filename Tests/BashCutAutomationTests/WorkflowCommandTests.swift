import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

/// The recipe-driven workflow's commands (spec 13): run append's fields, run checklist, review packet points, the
/// review exit status and the guard categories.
struct WorkflowCommandTests {
    @Test("run append takes stage status/evidence/reason, skill name and hook flag, and audit point/verdict/findings/by")
    func runAppendParameters() throws {
        let spec = try #require(CommandCatalog.spec(named: "run.append"))
        let flags = Dictionary(uniqueKeysWithValues: spec.parameters.compactMap { parameter -> (String, String)? in
            guard case .option(let flag) = parameter.cli else { return nil }
            return (parameter.name, flag)
        })
        #expect(flags["status"] == "status" && flags["evidence"] == "evidence" && flags["reason"] == "reason")
        #expect(flags["name"] == "name" && flags["verifiedBy"] == "verified-by")
        #expect(flags["point"] == "point" && flags["verdict"] == "verdict" && flags["findings"] == "findings" && flags["by"] == "by")
        let values = try spec.validate([
            "kind": .string("audit"), "point": .string("draft"), "verdict": .string("pass"), "findings": .integer(2),
            "by": .string("critic"),
        ])
        #expect(values["verdict"] == .string("pass"))
        #expect(throws: RPCFailure.self) { try spec.validate(["kind": .string("audit"), "verdict": .string("ok")]) }
        #expect(throws: RPCFailure.self) { try spec.validate(["kind": .string("stage"), "status": .string("started")]) }
        #expect(CommandCatalog.spec(named: "run.checklist")?.mode == .read)
        let packet = try #require(CommandCatalog.spec(named: "review.packet"))
        #expect(packet.parameters.first { $0.name == "point" }?.choices == ["strategy", "draft", "process"])
    }

    @Test("review run --summary exits 0 on pass, 1 on fail and 2 on incomplete; other commands 0")
    func reviewExitStatus() {
        let result = { (status: String) in JSONValue.object(["summary": .object(["status": .string(status)])]) }
        #expect(CommandCatalog.exitStatus(method: "review.run", result: result("pass")) == 0)
        #expect(CommandCatalog.exitStatus(method: "review.run", result: result("fail")) == 1)
        #expect(CommandCatalog.exitStatus(method: "review.run", result: result("incomplete")) == 2)
        #expect(CommandCatalog.exitStatus(method: "review.run", result: .array([])) == 0)
        #expect(CommandCatalog.exitStatus(method: "run.checklist", result: result("fail")) == 0)
    }

    @Test("Guard failures are typed audit_missing or recipe_unread, not retryable, with the thrower's remediation")
    func guardCategories() {
        let failure = RPCFailure(-32003, "needs a draft audit", category: .auditMissing, data: [
            "remediation": .object(["command": .string("review packet --point draft")]),
        ]).typed
        let data = failure.data?.object ?? [:]
        #expect(data["category"] == .string("audit_missing") && data["retryable"] == .bool(false))
        #expect(data["remediation"]?.object["command"] == .string("review packet --point draft"))
        #expect(RPCErrorCategory(rawValue: "recipe_unread") == .recipeUnread)
    }
}
