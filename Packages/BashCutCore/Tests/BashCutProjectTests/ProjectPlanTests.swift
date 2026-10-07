import Foundation
import Testing

@testable import BashCutProject

/// The brief and the edit plan as project data (P1-D1, P1-D2).
struct ProjectPlanTests {
    let brief: JSONValue = .object([
        "goal": .object(["value": .string("Food tour"), "status": .string("stated")]),
        "lengthSeconds": .object(["value": .object(["min": .number(30), "max": .number(45)]), "status": .string("inferred")]),
        "outputs": .object(["value": .array([.string("tiktok")]), "status": .string("confirmed"), "source": .string("chat")]),
        "ideas": .array([.object(["text": .string("open on the stall")])]),
    ])
    let plan: JSONValue = .object([
        "mode": .string("create"), "stage": .string("draft"),
        "sections": .array([
            .object(["id": .string("hook"), "label": .string("Hook"),
                     "lengthSeconds": .object(["min": .number(1), "max": .number(3)]), "frozen": .bool(true)]),
            .object(["id": .string("body"), "label": .string("B")]),
        ]),
        "shots": .array([.object(["id": .string("s1"), "purpose": .string("open"), "size": .string("CU"),
                                 "source": .string("footage"), "mustShow": .array([.string("bánh mì")])])]),
        "beats": .array([.object(["id": .string("b1"), "section": .string("hook"), "text": .string("Ăn gì?")])]),
        "ranges": .object(["maxShotSeconds": .object(["min": .number(2), "max": .number(4), "reason": .string("fast")])]),
    ])

    @Test("A valid brief and plan pass; malformed fields name their path")
    func validation() throws {
        var project = ReviewSequenceTests().project()
        project["brief"] = brief
        project["plan"] = plan
        try project.validate()
        let bad: [(String, JSONValue)] = [
            ("brief", .object(["goal": .object(["value": .string("x"), "status": .string("guessed")])])),
            ("brief", .object(["mood": .object(["value": .string("x"), "status": .string("stated")])])),
            ("plan", .object(["mode": .string("auto")])),
            ("plan", .object(["sections": .array([.object(["id": .string("a")])])])),
            ("plan", .object(["sections": .array([.object(["id": .string("a"), "label": .string("A")]),
                                                  .object(["id": .string("a"), "label": .string("B")])])])),
            ("plan", .object(["shots": .array([.object(["id": .string("s"), "purpose": .string("p"), "size": .string("XL")])])])),
            ("plan", .object(["ranges": .object(["x": .object(["min": .number(3), "max": .number(1)])])])),
        ]
        for (key, value) in bad {
            var copy = project
            copy[key] = value
            #expect(throws: ProjectError.self) { try copy.validate() }
        }
    }

    @Test("Review compares the brief's length and outputs and each planned section with what was cut, as info")
    func review() throws {
        var project = ReviewSequenceTests().project()
        project["brief"] = brief
        project["plan"] = plan
        project.markers = [TimelineMarker(at: 0, kind: "section", label: "Hook"), TimelineMarker(at: 120, kind: "section", label: "B")]
        let issues = TimelineReview.planIssues(project)
        let byID = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        #expect(issues.allSatisfy { $0.severity == .info })
        #expect(byID["brief-length"]?.detail.contains("7.0 s") == true)
        #expect(byID["brief-outputs"]?.fix?.command == "project.format")
        #expect(byID["plan-section-hook"]?.detail == "Planned 1–3 s, measured 4.0 s.")
        #expect(byID["plan-section-body"] == nil)
    }

    @Test("The summary names the brief's goal, outputs and length and counts the plan")
    func summary() {
        var project = Project(name: "Plan", fps: FrameRate(30, 1))
        #expect(ProjectPlan.summary(project) == .object([:]))
        project["brief"] = brief
        project["plan"] = plan
        let json = ProjectPlan.summary(project).object
        #expect(json["brief"]?.object.keys.sorted() == ["goal", "lengthSeconds", "outputs"])
        let row = json["plan"]?.object ?? [:]
        #expect(row["sections"] == .integer(2) && row["shots"] == .integer(1) && row["beats"] == .integer(1))
        #expect(row["mode"] == .string("create") && row["frozen"] == .array([.string("hook")]))
    }
}

/// The plan against what was measured (P1-D3).
struct PlanCoverageTests {
    @Test("Planned shots are placed, found or missing from the descriptions; facts only")
    func coverage() throws {
        var project = ReviewSequenceTests().project()
        project["plan"] = .object(["shots": .array([
            .object(["id": .string("wide"), "purpose": .string("establish"), "size": .string("MS")]),
            .object(["id": .string("close"), "purpose": .string("detail"), "size": .string("CU")]),
            .object(["id": .string("tagged"), "purpose": .string("x"), "size": .string("ECU")]),
            .object(["id": .string("none"), "purpose": .string("y"), "mustShow": .array([.string("bánh mì")])]),
        ])])
        let main = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[main].items[2]["planShot"] = .string("tagged")
        project.tracks[main].items.removeLast()
        let json = PlanCoverage.coverage(project).object
        let rows = Dictionary(uniqueKeysWithValues: (json["shots"]?.array ?? []).map { ($0.object["id"]?.string ?? "", $0.object) })
        #expect(rows["wide"]?["status"] == .string("placed") && rows["wide"]?["foundCount"] == .integer(2))
        #expect(rows["close"]?["status"] == .string("found"))
        #expect(rows["tagged"]?["placed"]?.array.first?.object["item"] == .string("c"))
        #expect(rows["none"]?["status"] == .string("missing"))
        #expect(json["summary"]?.object["missing"] == .integer(1))
    }

    @Test("Beats are found in the heard words with their share, place and section against the plan")
    func script() throws {
        var project = ReviewSequenceTests().project()
        project["plan"] = .object([
            "sections": .array([.object(["id": .string("b"), "label": .string("B")])]),
            "beats": .array([
                .object(["id": .string("1"), "text": .string("xin chào các bạn"), "section": .string("b")]),
                .object(["id": .string("2"), "text": .string("hôm nay ăn phở")]),
            ]),
        ])
        let words = ["xin", "chào", "mọi", "bạn"].enumerated().map { index, text in
            ReviewSync.WordSpan(at: 120 + index * 10, end: 128 + index * 10, text: text)
        }
        let json = PlanCoverage.scriptCheck(project, words: words).object
        let beats = (json["beats"]?.array ?? []).map(\.object)
        #expect(beats[0]["heardShare"] == .number(0.75) && beats[0]["at"] == .integer(120))
        #expect(beats[0]["inPlannedSection"] == .bool(true) && beats[0]["unmatched"] == .array([.string("các")]))
        #expect(beats[1]["heardShare"] == .number(0) && beats[1]["at"] == nil)
    }
}
