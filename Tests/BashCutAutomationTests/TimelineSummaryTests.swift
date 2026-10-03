import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct TimelineSummaryTests {
    private func project() -> Project {
        var project = Project(name: "Summary", fps: FrameRate(30, 1))
        var tracks = project.tracks
        tracks[0].items = [
            Item(id: "a", media: "m", at: 0, duration: 30), Item(id: "b", media: "m", at: 30, duration: 30),
        ]
        project.tracks = tracks
        project.transitions = [
            TimelineTransition(fields: [
                "id": .string("t1"), "kind": .string("whip"), "from": .string("a"), "to": .string("b"),
                "duration": .integer(12),
            ])
        ]
        project.markers = [TimelineMarker(id: "section-hook", at: 0, kind: "section", label: "Hook")]
        return project
    }

    @Test("timeline get lists transitions and markers so agents can check their own edits")
    func transitionsAndMarkers() {
        let json = TimelineSummary.json(project()).object
        #expect(json["transitions"]?.array.first?.object["kind"] == .string("whip"))
        #expect(json["markers"]?.array.first?.object["label"] == .string("Hook"))
        #expect(json["tracks"]?.array.isEmpty == false)

        let text = TimelineSummary.text(project())
        #expect(text.contains("MAIN a 0-30"))
        #expect(text.contains("TRANSITION t1 whip a->b dur=12"))
        #expect(text.contains("MARKER section-hook section at=0 Hook"))
    }
}

struct LogSummaryTests {
    @Test("The debug-log summary is compact JSON and stops at the limit for large results")
    func boundedSummary() {
        #expect(CommandRegistry.summary(["b": .integer(1), "a": .string("x\"y")]) == #"{"a":"x\"y","b":1}"#)
        let big = JSONValue.array((0..<100_000).map { .object(["id": .string("item-\($0)")]) })
        let text = CommandRegistry.summary(big)
        #expect(text.count <= 401)
        #expect(text.hasSuffix("…"))
    }
}
