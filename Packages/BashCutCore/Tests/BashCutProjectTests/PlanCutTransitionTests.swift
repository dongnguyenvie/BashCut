import Foundation
import Testing

@testable import BashCutProject

/// Transitions in `plan.cut` and what a later apply keeps (#623).
struct PlanCutTransitionTests {
    /// Clips a and b on Main, title t on b, graphic g1 over b (media `m`, or `graphic` for g1 when given).
    func list(_ extra: String = "", graphic: String = "m", cut: String = "", title: String = "") -> String {
        #"""
        {"clips":[{"id":"a","media":"m","from":0,"to":2},{"id":"b","media":"m","from":5,"to":7\#(cut)}],
        "titles":[{"id":"t","text":"Hi","clip":"b","seconds":1\#(title)}],
        "graphics":[{"id":"g1","media":"\#(graphic)","on":"b","seconds":1}]\#(extra)}
        """#
    }

    func project() -> Project {
        var project = PlanCutTests().project()
        var copy = project.media[0]
        copy["id"] = .string("m2")
        project.media.append(copy)
        return project
    }

    func build(_ json: String, on project: Project) throws -> Project {
        let spec = try PlanCutTests().spec(json)
        let built = try PlanCut.build(spec, clips: PlanCut.resolve(spec, project: project, transcripts: [:]).clips, on: project)
        return try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
    }

    func item(_ id: String, _ project: Project) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    /// The plan applied, then a cut transition into b and the graphic's and title's In/Out set by hand.
    func handEdited() throws -> Project {
        let project = try build(list(), on: project())
        return try project.applying(.group(label: "Hand", author: .user, ops: [
            .upsertTransition(id: "", kind: "whip", from: "plan-a", to: "plan-b", duration: 6),
            .setProperties(item: "plan-g1", patch: [
                "enter": .object(["kind": .string("wipe"), "duration": .integer(6)]),
                "exit": .object(["kind": .string("iris"), "duration": .integer(8)]),
            ]),
            .setProperties(item: "plan-t", patch: ["enter": .object(["kind": .string("slide"), "duration": .integer(5)])]),
        ])).project
    }

    @Test("A clip's transition becomes the cut into it; a title's and a graphic's enter/exit their In and Out")
    func fromPlan() throws {
        let json = list(
            cut: #","transition":"dissolve:9""#, title: #","enter":"slide","exit":{"kind":"dissolve","duration":4,"easing":"inOut"}"#)
            .replacingOccurrences(of: #""seconds":1}]}"#, with: #""seconds":1,"enter":"wipe:12"}]}"#)
        let after = try build(json, on: project())
        let cut = try #require(after.transitions.first { $0.toItemID == "plan-b" })
        #expect(cut.id == "plan-tx-b" && cut.kind == "dissolve" && cut.duration == 9 && cut.fromItemID == "plan-a")
        let title = try item("plan-t", after)
        #expect(title.enterTransition?.kind == "slide" && title.enterTransition?.duration == 10, "half a second, at most a third")
        #expect(title.exitTransition == ItemTransition(kind: "dissolve", duration: 4, easing: "inOut"))
        #expect(try item("plan-g1", after).enterTransition == ItemTransition(kind: "wipe", duration: 12))
        #expect(PlanCut.transitionProblems(try PlanCutTests().spec(json), on: after).isEmpty)
    }

    @Test("Applying again (a captions patch) keeps the cut transition and In/Out set by hand on the rebuilt items")
    func keptThroughReapply() throws {
        let after = try build(list(#","captions":{"wordStyle":"highlight"}"#), on: try handEdited())
        let cut = try #require(after.transitions.first { $0.toItemID == "plan-b" })
        #expect(cut.kind == "whip" && cut.duration == 6 && cut.fromItemID == "plan-a")
        #expect(try item("plan-g1", after).enterTransition?.kind == "wipe")
        #expect(try item("plan-g1", after).exitTransition?.kind == "iris")
        #expect(try item("plan-t", after).enterTransition?.kind == "slide")
    }

    @Test("A graphic re-rendered (new media in its row) keeps its In and Out")
    func keptThroughGraphicReplace() throws {
        let after = try build(list(graphic: "m2"), on: try handEdited())
        let graphic = try item("plan-g1", after)
        #expect(graphic["media"] == .string("m2"))
        #expect(graphic.enterTransition == ItemTransition(kind: "wipe", duration: 6))
        #expect(graphic.exitTransition == ItemTransition(kind: "iris", duration: 8))
    }

    @Test("The plan wins over what was set by hand; dropping it from the plan removes it; a gone row loses its own")
    func planOverrides() throws {
        let set = try build(list(cut: #","transition":{"kind":"dissolve","duration":5}"#, title: #","enter":"none""#),
                            on: try handEdited())
        #expect(set.transitions.filter { $0.toItemID == "plan-b" }.map(\.kind) == ["dissolve"])
        #expect(try item("plan-t", set).enterTransition == nil)
        #expect(try item("plan-g1", set).enterTransition?.kind == "wipe", "the plan does not set it, so the hand one stays")
        let dropped = try build(list(), on: set)
        #expect(dropped.transitions.isEmpty, "the plan's own transition goes with it")
        let gone = try build(#"{"clips":[{"id":"a","media":"m","from":0,"to":2}]}"#, on: try handEdited())
        let items: [Item] = gone.tracks.flatMap(\.items)
        #expect(gone.transitions.isEmpty)
        #expect(items.allSatisfy { $0.enterTransition == nil })
    }

    @Test("plan check lists every entry it cannot read at once: an unknown kind, a bad duration, other field errors")
    func allProblemsAtOnce() throws {
        let json = #"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"speed":99},{"id":"b","media":"m","from":5,"to":7,"transition":"warp:9"}],
            "titles":[{"id":"t","text":"Hi","clip":"a","seconds":1,"enter":{"kind":"dissolve","duration":0}},
            {"id":"u","text":"Yo","clip":"nope","seconds":1}],
            "graphics":[{"id":"g1","media":"m","on":"b","seconds":1,"exit":"iris:x"}]}
            """#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let spec = try PlanCut.decodeAll(value)
        #expect(spec.invalid.compactMap(\.entry).sorted() == ["a", "b", "g1", "t", "u"])
        #expect(spec.invalid.allSatisfy { $0.severity == "error" })
        #expect(spec.invalid.first { $0.entry == "b" }?.detail.contains("warp") == true)
        #expect(spec.clips.map(\.id) == ["b"], "a clip with a wrong transition stays, its error reported")
        #expect(PlanCut.resolve(spec, project: project(), transcripts: [:]).problems.count(where: { $0.id == "entry-invalid" }) == 5)
        #expect(throws: ProjectError.self) { try PlanCut.decode(value) }
    }

    @Test("A transition with no cut before it, or longer than the cut allows, is an error of plan check")
    func transitionNotSet() throws {
        let json = #"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"transition":"dissolve"},
            {"id":"b","media":"m","from":5,"to":7,"transition":"dissolve:90"}]}
            """#
        let after = try build(json, on: project())
        let problems = PlanCut.transitionProblems(try PlanCutTests().spec(json), on: after)
        #expect(problems.map(\.id) == ["transition-no-cut", "transition-too-long"])
        #expect(problems.map(\.entry) == ["a", "b"] && problems[1].facts["maxFrames"] == .integer(60))
        #expect(after.transitions.isEmpty)
    }
}
