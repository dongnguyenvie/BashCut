import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// The derived checklist, `workflow.next` and the two guards (spec 13 §5, §7).
struct WorkflowChecklistTests {
    private func project(plan: JSONValue? = nil) throws -> Project {
        var project = try ProjectFixtures.linkedPair()
        project["plan"] = plan
        return project
    }

    private func entry(_ kind: String, run: Int = 1, _ fields: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var entry = fields
        entry["kind"] = .string(kind)
        entry["run"] = .integer(run)
        return entry
    }

    private func rows(_ checklist: JSONValue) -> [String: [String: JSONValue]] {
        Dictionary(uniqueKeysWithValues: (checklist.object["stages"]?.array ?? []).map {
            ($0.object["id"]?.string ?? "", $0.object)
        })
    }

    @Test("Stages come from the kit's table and the plan; skill reads, status, evidence and n/a are derived")
    func checklist() throws {
        let plan: JSONValue = .object([
            "recipe": .object(["skill": .string("bashcut.vlog:product-ad")]),
            "stages": .object([
                "voiceover": .object(["required": .bool(true)]),
                "colour": .object(["required": .bool(false), "why": .string("screen recording")]),
                "motion-graphics": .object(["required": .bool(true), "why": .string("price card")]),
                "captions": .object(["rules": .array([.string("no captions over titles")])]),
            ]),
        ])
        let project = try project(plan: plan)
        let entries = [
            entry("note", run: 0),
            entry("skill", run: 0, ["name": .string("bashcut.vlog:product-ad"), "origin": .string("plugin")]),
            entry("start"),
            entry("skill", ["name": .string("footage-survey"), "origin": .string("kit")]),
            entry("stage", ["stage": .string("survey"), "status": .string("done"),
                            "evidence": .array([.string("survey/sheet.png")])]),
            entry("skill", ["name": .string("bc:rough-cut"), "verified": .bool(false)]),
            entry("stage", ["stage": .string("rough-cut"), "status": .string("done"), "unverified": .bool(true)]),
            entry("stage", ["stage": .string("voiceover"), "status": .string("skipped"), "reason": .string("user speech")]),
        ]
        let checklist = WorkflowChecklist.json(project, entries: entries)
        let stages = rows(checklist)
        let ids = (checklist.object["stages"]?.array ?? []).compactMap { $0.object["id"]?.string }
        #expect(ids.first == "intake" && ids.last == "learn")
        #expect(ids.firstIndex(of: "motion-graphics") == ids.firstIndex(of: "review").map { $0 - 1 })
        #expect(stages["motion-graphics"]?["skill"] == .string("bc:motion-graphics"))
        #expect(stages["survey"]?["skillRead"] == .bool(true) && stages["survey"]?["status"] == .string("done"))
        #expect(stages["survey"]?["evidence"]?.array.count == 1)
        #expect(stages["rough-cut"]?["skillReadUnverified"] == .bool(true))
        #expect(stages["colour"]?["status"] == .string("n/a") && stages["colour"]?["by"] == .string("recipe"))
        #expect(stages["colour"]?["reason"] == .string("screen recording") && stages["colour"]?["skill"] == nil)
        #expect(stages["captions"]?["rules"]?.array.count == 1)
        #expect(stages["effects"]?["status"] == .string("pending") && stages["effects"]?["required"] == nil)
        let open = (checklist.object["open"]?.array ?? []).compactMap(\.string)
        #expect(open.contains("voiceover: required stage skipped"))
        #expect(open.contains("rough-cut: done without evidence"))
        #expect(open.contains("intake: required stage not done") && open.contains("story: required stage not done"))
        #expect(open.contains("strategy audit missing") && !open.contains("draft audit missing"))
        #expect(!open.contains { $0.hasPrefix("recipe") })
        #expect(checklist.object["audits"] == .object(["strategy": .null, "draft": .null, "process": .null]))

        let next = WorkflowChecklist.next(checklist).object
        #expect(next["stage"] == .string("intake") && next["skill"] == .string("bc:edit-workflow"))
        #expect(next["skillRead"] == .bool(false) && next["recipe"] == nil)
        let compact = WorkflowChecklist.compact(checklist).object
        #expect(compact["stages"]?.array.contains(.string("rough-cut: done (unverified)")) == true)
        #expect(compact["openCount"]?.int == open.count)
    }

    @Test("Audits: the latest verdict per point; a draft audit goes stale when the timeline changes")
    func audits() throws {
        var project = try project(plan: .object(["recipe": .object(["skill": .string("bashcut.vlog:food")])]))
        let fingerprint = WorkflowChecklist.timelineFingerprint(project)
        let entries = [
            entry("audit", ["point": .string("strategy"), "verdict": .string("changes"), "by": .string("critic")]),
            entry("audit", ["point": .string("draft"), "verdict": .string("pass"), "by": .string("self"),
                            "timeline": .string(fingerprint)]),
            entry("stage", ["stage": .string("review"), "status": .string("done"), "evidence": .array([.string("r")])]),
        ]
        var checklist = WorkflowChecklist.json(project, entries: entries).object
        #expect(checklist["audits"]?.object["strategy"] == .string("changes"))
        #expect(checklist["auditDetails"]?.object["draft"]?.object["by"] == .string("self"))
        #expect(checklist["auditDetails"]?.object["draft"]?.object["current"] == .bool(true))
        var open = (checklist["open"]?.array ?? []).compactMap(\.string)
        #expect(open.contains("strategy audit: changes") && open.contains { $0.hasPrefix("recipe bashcut.vlog:food") })
        #expect(WorkflowChecklist.next(.object(checklist)).object["recipe"] == .string("bashcut.vlog:food"))
        // Notes do not count as a change; a trim does.
        project["plan"] = .object(["mode": .string("create")])
        #expect(WorkflowChecklist.timelineFingerprint(project) == fingerprint)
        project = try project.applying(.trim(item: "v", edge: .end, toFrame: 30, ripple: false)).project
        checklist = WorkflowChecklist.json(project, entries: entries).object
        open = (checklist["open"]?.array ?? []).compactMap(\.string)
        #expect(open.contains("draft audit is older than the last edit"))
        #expect(open.contains("process audit missing") == false)
    }

    @Test("A final export needs a passing draft audit of this timeline, or the user's G5 approval")
    func draftGuard() throws {
        var project = try project()
        #expect(WorkflowChecklist.draftGuard(project, entries: [])?.category == "audit_missing")
        #expect(WorkflowChecklist.draftGuard(project, entries: [])?.command == "review packet --point draft")
        let changes = entry("audit", ["point": .string("draft"), "verdict": .string("changes"),
                                      "timeline": .string(WorkflowChecklist.timelineFingerprint(project))])
        #expect(WorkflowChecklist.draftGuard(project, entries: [changes])?.message.contains("changes") == true)
        let pass = entry("audit", ["point": .string("draft"), "verdict": .string("pass"), "by": .string("self"),
                                   "timeline": .string(WorkflowChecklist.timelineFingerprint(project))])
        #expect(WorkflowChecklist.draftGuard(project, entries: [changes, pass]) == nil)
        project = try project.applying(.trim(item: "v", edge: .end, toFrame: 30, ripple: false)).project
        #expect(WorkflowChecklist.draftGuard(project, entries: [pass])?.category == "audit_missing")
        let approved = entry("gate", ["gate": .string("G5"), "event": .string("approved"), "rev": .integer(project.revision)])
        #expect(WorkflowChecklist.draftGuard(project, entries: [pass, approved]) == nil)
        let older = entry("gate", ["gate": .string("G5"), "event": .string("approved"), "rev": .integer(project.revision - 1)])
        #expect(WorkflowChecklist.draftGuard(project, entries: [older]) != nil)
    }

    @Test("G2 needs the plan's recipe read and a strategy audit of any verdict")
    func strategyGuard() throws {
        let plain = try project()
        #expect(WorkflowChecklist.strategyGuard(plain, entries: [])?.category == "audit_missing")
        #expect(WorkflowChecklist.strategyGuard(plain, entries: [])?.command == "review packet --point strategy")
        let audit = entry("audit", ["point": .string("strategy"), "verdict": .string("changes")])
        #expect(WorkflowChecklist.strategyGuard(plain, entries: [audit]) == nil)
        let recipe = try project(plan: .object(["recipe": .object(["skill": .string("bashcut.vlog:product-ad")])]))
        let unread = WorkflowChecklist.strategyGuard(recipe, entries: [audit])
        #expect(unread?.category == "recipe_unread" && unread?.command == "skills get bashcut.vlog:product-ad")
        let read = entry("skill", ["name": .string("bashcut.vlog:product-ad"), "origin": .string("plugin")])
        #expect(WorkflowChecklist.strategyGuard(recipe, entries: [read, audit]) == nil)
        #expect(WorkflowChecklist.strategyGuard(recipe, entries: [read])?.category == "audit_missing")
    }

    @Test("The plan summary carries the recipe, promise, checks and required or n/a stages")
    func planSummary() throws {
        let project = try project(plan: .object([
            "recipe": .object(["skill": .string("bashcut.vlog:product-ad"), "version": .string("0.0.1")]),
            "promise": .object(["hook": .string("Can one prompt cut an ad?"), "payoff": .string("Yes")]),
            "checks": .array([.object(["id": .string("one-message")]), .object(["id": .string("cta")])]),
            "stages": .object([
                "voiceover": .object(["required": .bool(true)]), "colour": .object(["required": .bool(false)]),
            ]),
        ]))
        let plan = ProjectPlan.summary(project).object["plan"]?.object ?? [:]
        #expect(plan["recipe"] == .string("bashcut.vlog:product-ad"))
        #expect(plan["promise"]?.object["payoff"] == .string("Yes"))
        #expect(plan["checks"] == .integer(2))
        #expect(plan["requiredStages"] == .array([.string("voiceover")]) && plan["naStages"] == .array([.string("colour")]))
    }
}
