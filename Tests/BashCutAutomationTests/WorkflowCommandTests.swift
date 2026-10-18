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
        #expect(throws: RPCFailure.self) { try spec.validate(["kind": .string("stage"), "status": .string("finished")]) }
        #expect(try spec.validate(["kind": .string("stage"), "status": .string("started")])["status"] == .string("started"))
        #expect(CommandCatalog.spec(named: "run.checklist")?.mode == .read)
        let packet = try #require(CommandCatalog.spec(named: "review.packet"))
        #expect(packet.parameters.first { $0.name == "point" }?.choices == ["strategy", "draft", "process"])
    }

    @Test("run append reports a stage with step text, progress and ETA in one call; run status reads the panel")
    @MainActor func runProgress() throws {
        let parsed = try CommandLineParser.parse([
            "run", "append", "stage", "--stage", "cut", "--text", "Cutting", "--progress", "0.5", "--eta", "90",
        ])
        #expect(parsed.spec.name == "run.append" && parsed.spec.mode == .ui)
        #expect(parsed.params["stage"] == .string("cut") && parsed.params["eta"] == .integer(90))
        #expect(parsed.params["progress"]?.double == 0.5)
        #expect(throws: RPCFailure.self) { try parsed.spec.validate(["kind": .string("stage"), "progress": .number(2)]) }
        #expect(CommandCatalog.spec(named: "run.status")?.mode == .read)
        #expect(ChatCommandSession.allowedMethods.contains("run.status"))
        #expect(CommandCatalog.hiddenFromAgents.contains("run.status"))
    }

    @Test("export reveal-output reveals a run's file by ledger ID, index or path, like the result card's icon")
    @MainActor func revealOutput() throws {
        let parsed = try CommandLineParser.parse(["export", "reveal-output", "--export", "/tmp/a.mp4"])
        #expect(parsed.spec.name == "export.reveal-output" && parsed.spec.mode == .ui)
        #expect(parsed.params["export"] == .string("/tmp/a.mp4"))
        #expect(CommandCatalog.hiddenFromAgents.contains("export.reveal-output"))
    }

    @Test("review run takes a frame range; quick edits are the user's, not the agents'")
    @MainActor func rangeAndQuickEdit() throws {
        let review = try CommandLineParser.parse(["review", "run", "--summary", "--from", "360", "--to", "540"])
        #expect(review.params["from"] == .integer(360) && review.params["to"] == .integer(540))
        let quick = try CommandLineParser.parse(["agent", "quick-edit", "music-lower", "--items", "v1,v2", "--text", "softer"])
        #expect(quick.spec.name == "agent.quick-edit" && quick.params["kind"] == .string("music-lower"))
        #expect(throws: RPCFailure.self) { try quick.spec.validate(["kind": .string("slower")]) }
        #expect(CommandCatalog.hiddenFromAgents.contains("agent.quick-edit"))
        #expect(!ChatCommandSession.allowedMethods.contains("agent.quick-edit"))
        for id in ["run.show", "run.dismiss", "run.fix-issues", "run.another-recipe"] {
            #expect(UIAction.matching(id).count == 1)
        }
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

    @Test("Guard failures are typed audit_missing, recipe_unread, graphics_draft or stage_pending, not retryable, with the thrower's remediation")
    func guardCategories() {
        let failure = RPCFailure(-32003, "needs a draft audit", category: .auditMissing, data: [
            "remediation": .object(["command": .string("review packet --point draft")]),
        ]).typed
        let data = failure.data?.object ?? [:]
        #expect(data["category"] == .string("audit_missing") && data["retryable"] == .bool(false))
        #expect(data["remediation"]?.object["command"] == .string("review packet --point draft"))
        #expect(RPCErrorCategory(rawValue: "recipe_unread") == .recipeUnread)
        #expect(RPCErrorCategory(rawValue: "graphics_draft") == .graphicsDraft)
        #expect(RPCErrorCategory.graphicsDraft.retryable == false)
        #expect(RPCErrorCategory(rawValue: "stage_pending") == .stagePending)
        #expect(RPCErrorCategory.stagePending.retryable == false)
    }
}
