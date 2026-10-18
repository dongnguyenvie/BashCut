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

    @Test("A final export refuses graphics rendered as drafts, naming them and the plugin's final render (#634)")
    func graphicsDraftGuard() throws {
        var project = try project()
        #expect(WorkflowChecklist.graphicsDraftGuard(project) == nil)
        project = try project.applying(.setMediaData(media: "m", patch: ["take": .integer(2)])).project
        #expect(WorkflowChecklist.graphicsDraftGuard(project) == nil)
        let final: JSONValue = .object(["composition": .string("diagram"), "name": .string("Flow"), "fps": .integer(30)])
        project = try project.applying(.setMediaData(media: "m", patch: ["graphics": final])).project
        #expect(WorkflowChecklist.graphicsDraftGuard(project) == nil)

        var draft = final.object
        draft["draft"] = .bool(true)
        project = try project.applying(.setMediaData(media: "m", patch: ["graphics": .object(draft)])).project
        let failure = try #require(WorkflowChecklist.graphicsDraftGuard(project))
        #expect(failure.category == "graphics_draft")
        #expect(failure.command == "bin/graphic rerender --all --final")
        #expect(failure.message.contains("Flow (media m; items v, a)"))
        #expect(WorkflowChecklist.graphicDrafts(project) == [.init(media: "m", name: "Flow", items: ["v", "a"])])
        #expect(failure.details["drafts"]?.array.first?.object["items"] == .array([.string("v"), .string("a")]))

        // Every draft is a plan.cut graphic's media: the plan's final render fixes it.
        project["plan"] = .object(["cut": .object(["graphics": .array([.object(["id": .string("g1"), "media": .string("m")])])])])
        #expect(WorkflowChecklist.graphicsDraftGuard(project)?.command == "bin/graphic plan --final")

        // A draft no item uses is not exported (deleting the clip takes its linked sound too).
        project = try project.applying(.delete(item: "v", ripple: false)).project
        #expect(WorkflowChecklist.graphicsDraftGuard(project) == nil)
    }

    @Test("Finalising draft graphics keeps the draft audit; changing a graphic's inputs does not (#634)")
    func graphicFinalKeepsAudit() throws {
        // Two uses of a 2.5 s lower third rendered as a draft (15 fps, 38 frames): one played through, one from 7.
        let recorded: [String: JSONValue] = [
            "composition": .string("/c/lower-third"), "name": .string("lower-third"), "fps": .integer(30),
            "variables": .object(["title": .string("Hi")]), "seconds": .number(2.5),
        ]
        func graphic(_ id: String, fps: Int, frames: Int, draft: Bool) -> Media {
            var media = ProjectFixtures.media(id, path: "\(id).mov", frames: frames, fps: FrameRate(fps, 1), kind: "video")
            var graphics = recorded
            graphics["frames"] = .integer(frames)
            if draft { graphics["draft"] = .bool(true) }
            media.fields["data"] = .object(["graphics": .object(graphics)])
            return media
        }
        var project = try project().applying(
            .group(
                label: "Draft", author: .agent,
                ops: [
                    .addMedia(graphic("draft", fps: 15, frames: 38, draft: true)),
                    .insert(track: "v1", item: Item(id: "g", media: "draft", at: 60, duration: 76)),
                    .insert(track: "v1", item: Item(id: "h", media: "draft", at: 136, duration: 20, sourceIn: 7)),
                ])
        ).project
        let pass = entry("audit", ["point": .string("draft"), "verdict": .string("pass"), "by": .string("critic"),
                                   "timeline": .string(WorkflowChecklist.timelineFingerprint(project))])
        #expect(WorkflowChecklist.draftGuard(project, entries: [pass]) == nil)

        // graphic plan --final: new media at 30 fps (75 frames), in-points rescaled, the played-through use trimmed.
        project = try project.applying(
            .group(
                label: "Final graphics", author: .agent,
                ops: [
                    .addMedia(graphic("final", fps: 30, frames: 75, draft: false)),
                    .setSource(item: "g", media: "final", sourceIn: 0, reversed: nil),
                    .setSource(item: "h", media: "final", sourceIn: 14, reversed: nil),
                    .trim(item: "g", edge: .end, toFrame: 135, ripple: false),
                ])
        ).project
        #expect(WorkflowChecklist.graphicDrafts(project).isEmpty)
        #expect(WorkflowChecklist.draftGuard(project, entries: [pass]) == nil)

        // A shorter use, a slip or new text is a change the audit has not seen.
        for change: EditOperation in [
            .trim(item: "g", edge: .end, toFrame: 120, ripple: false), .slip(item: "h", sourceIn: 20),
            .setMediaData(media: "final", patch: ["graphics": .object(recorded.merging(["variables": .object(["title": .string("Bye")])]) { $1 })]),
        ] {
            let changed = try project.applying(change).project
            #expect(WorkflowChecklist.draftGuard(changed, entries: [pass])?.category == "audit_missing")
        }
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

    @Test("Review, G5 and a final export wait for every stage the plan requires before review")
    func stagesGuard() throws {
        let project = try project(plan: .object([
            "stages": .object([
                "effects": .object(["required": .bool(true), "why": .string("zoom onto the panel in use")]),
                "sound": .object(["required": .bool(true)]),
                "colour": .object(["required": .bool(false)]),
                "visuals": .object(["after": .string("voiceover"), "required": .bool(true)]),
                "learn": .object(["required": .bool(true)]),
            ]),
        ]))
        let pass = entry("audit", ["point": .string("draft"), "verdict": .string("pass"), "by": .string("critic"),
                                   "timeline": .string(WorkflowChecklist.timelineFingerprint(project))])
        let sound = entry("stage", ["stage": .string("sound")])
        let failure = try #require(WorkflowChecklist.stagesGuard(project, entries: [sound, pass]))
        #expect(failure.category == "stage_pending" && failure.command == "run checklist")
        // In table order; learn comes after review and colour is n/a.
        #expect(failure.details["stages"] == .array([
            .object(["id": .string("visuals"), "status": .string("pending")]),
            .object(["id": .string("sound"), "status": .string("started")]),
            .object(["id": .string("effects"), "status": .string("pending")]),
        ]))
        #expect(failure.message.contains("effects (pending)"))
        #expect(WorkflowChecklist.draftGuard(project, entries: [sound, pass])?.category == "stage_pending")

        // Done or skipped with a reason closes a stage; an earlier run's entries do not count.
        let closed = [
            entry("stage", run: 1, ["stage": .string("visuals"), "status": .string("done")]),
            entry("stage", run: 2, ["stage": .string("visuals"), "status": .string("done")]),
            entry("stage", run: 2, ["stage": .string("sound"), "status": .string("done"), "evidence": .array([.string("mix")])]),
            entry("stage", run: 2, ["stage": .string("effects"), "status": .string("skipped"), "reason": .string("no zoom")]),
        ]
        #expect(WorkflowChecklist.pendingRequiredStages(project, entries: Array(closed.dropFirst())).isEmpty)
        #expect(WorkflowChecklist.draftGuard(project, entries: Array(closed.dropFirst()) + [entry("audit", run: 2, pass)]) == nil)
        let stale = WorkflowChecklist.pendingRequiredStages(project, entries: [closed[0], entry("start", run: 2)])
        #expect(stale.count == 3)

        // The user's G5 approval at this revision still overrides.
        let approved = entry("gate", ["gate": .string("G5"), "event": .string("approved"), "rev": .integer(project.revision)])
        #expect(WorkflowChecklist.draftGuard(project, entries: [pass, approved]) == nil)
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

    @Test("Only marking the rough cut done while G2 is skipped is gated; progress reports never are")
    func stageGuardScope() {
        #expect(WorkflowChecklist.stageNeedsStrategyGuard(stage: "rough-cut", status: "done", strategySkipped: true))
        #expect(!WorkflowChecklist.stageNeedsStrategyGuard(stage: "rough-cut", status: nil, strategySkipped: true))
        #expect(!WorkflowChecklist.stageNeedsStrategyGuard(stage: "rough-cut", status: "started", strategySkipped: true))
        #expect(!WorkflowChecklist.stageNeedsStrategyGuard(stage: "rough-cut", status: "skipped", strategySkipped: true))
        #expect(!WorkflowChecklist.stageNeedsStrategyGuard(stage: "rough-cut", status: "done", strategySkipped: false))
        #expect(!WorkflowChecklist.stageNeedsStrategyGuard(stage: "colour", status: "done", strategySkipped: true))
    }

    @Test("A plan stage goes right after the stage its after names, chained or not, else before review")
    func stagePlacement() throws {
        let plan: JSONValue = .object([
            "stages": .object([
                "visuals": .object(["after": .string("voiceover")]),
                "visuals-check": .object(["after": .string("visuals"), "skill": .string("bashcut.vlog:plan")]),
                "b-roll": .object(["after": .string("voiceover")]),
                "motion-graphics": .object(["required": .bool(true)]),
                "orphan": .object(["after": .string("nowhere")]),
            ]),
        ])
        let checklist = WorkflowChecklist.json(try project(plan: plan), entries: [])
        let ids = (checklist.object["stages"]?.array ?? []).compactMap { $0.object["id"]?.string }
        let voiceover = try #require(ids.firstIndex(of: "voiceover"))
        #expect(Array(ids[voiceover...].prefix(5)) == ["voiceover", "b-roll", "visuals", "visuals-check", "sound"])
        let review = try #require(ids.firstIndex(of: "review"))
        #expect(Array(ids[(review - 2)..<review]) == ["motion-graphics", "orphan"])
        #expect(rows(checklist)["visuals"]?["skill"] == .string("bc:visual-plan"))
        #expect(rows(checklist)["visuals-check"]?["skill"] == .string("bashcut.vlog:plan"))
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

extension WorkflowChecklistTests {
    @Test("Review warns about each draft graphic with its items and the final render, so plan check sees it (#634)")
    func graphicDraftReview() throws {
        var project = try project()
        let final: JSONValue = .object(["composition": .string("diagram"), "name": .string("Flow"), "fps": .integer(30)])
        project = try project.applying(.setMediaData(media: "m", patch: ["graphics": final])).project
        #expect(!TimelineReview.run(project).contains { $0.kind == "graphic-draft" })

        var draft = final.object
        draft["draft"] = .bool(true)
        project = try project.applying(.setMediaData(media: "m", patch: ["graphics": .object(draft)])).project
        let issue = try #require(TimelineReview.run(project).first { $0.kind == "graphic-draft" })
        #expect(issue.id == "graphic-draft-m")
        #expect(issue.severity == .warning)
        #expect(issue.facts["items"] == .array([.string("v"), .string("a")]))
        #expect(issue.facts["command"] == .string("bin/graphic rerender --all --final"))
        #expect(issue.fix?.hint?.contains("bin/graphic rerender --all --final") == true)
        let items = project.tracks.flatMap(\.items).filter { ["v", "a"].contains($0.id) }
        #expect(issue.frame == items.map(\.at).min())
        #expect(issue.endFrame == items.map(\.end).max())
    }
}
