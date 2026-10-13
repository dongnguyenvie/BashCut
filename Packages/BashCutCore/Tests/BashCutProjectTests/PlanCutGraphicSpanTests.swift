import Foundation
import Testing

@testable import BashCutProject

/// The editor's graphic placeholders (#534) show where plan.cut graphics land on the edit as it is.
struct PlanCutGraphicSpanTests {
    @Test("Graphics span from their anchors' built items or from at; section graphics and missing anchors are left out")
    func spans() throws {
        var project = Project(name: "Explainer", fps: FrameRate(30, 1))
        var voice = Track(id: "vo", kind: "audio", role: TrackRole.voiceover)
        var first = Item(id: "plan-l1", media: "t1", at: 0, duration: 60)
        first[PlanCut.tag] = .string("l1")
        var second = Item(id: "plan-l2", media: "t2", at: 60, duration: 90)
        second[PlanCut.tag] = .string("l2")
        voice.items = [first, second]
        project.tracks = [voice]
        project["plan"] = .object(["sections": .array([.object(["id": .string("p1"), "label": .string("One")])])])
        let json = """
            {"clips": [], "voiceover": [{"id": "l1", "text": "One", "section": "p1"}, {"id": "l2", "text": "Two"},
              {"id": "l3", "text": "Three"}],
             "graphics": [{"id": "g1", "on": "l2", "seconds": 2}, {"id": "g2", "at": 1, "seconds": 1},
              {"id": "g3", "on": "l2"}, {"id": "g4", "on": "l3"}, {"id": "g5", "section": "p1"}]}
            """
        let spec = try PlanCut.decode(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        let spans = PlanCut.graphicSpans(spec, in: project)
        #expect(spans["g1"] == 60..<120)
        #expect(spans["g2"] == 30..<60)
        #expect(spans["g3"] == 60..<150)
        #expect(spans["g4"] == nil && spans["g5"] == nil)
    }
}
