import Foundation
import Testing

@testable import BashCutProject

/// `patchItems`: deep-merge restyles expanded into `setProperties` (Phase 2 restyle).
struct ItemPatchTests {
    private func project() throws -> Project {
        var first = Item(id: "c1", at: 0, duration: 30)
        first["text"] = .string("One")
        first["textStyle"] = .object(["color": .string("#FFFFFF"), "size": .number(0.05)])
        var second = Item(id: "c2", at: 30, duration: 30)
        second["text"] = .string("Two")
        second["textPreset"] = .string("bold")
        return try Project(name: "Patch").applying(.group(label: "Setup", author: .user, ops: [
            .insert(track: "t1", item: first), .insert(track: "t1", item: second),
        ])).project
    }

    @Test("A selector restyles every matching item; objects merge and null deletes a key")
    func selector() throws {
        let project = try project()
        let ops = try ItemPatch.expand([.object([
            "op": .string("patchItems"), "select": .object(["trackRole": .string("captions")]),
            "patch": .object(["textStyle": .object(["color": .string("#FFD400"), "size": .null])]),
        ])], in: project)
        #expect(ops.count == 2)
        let first = ops[0].object["patch"]?.object["textStyle"]
        #expect(first == .object(["color": .string("#FFD400")]))
        let second = ops[1].object["patch"]?.object["textStyle"]
        #expect(second == .object(["color": .string("#FFD400")]))
        let applied = try project.applying(.group(label: "Restyle", author: .agent, ops: ops.map { try EditOperation(json: $0) }))
        #expect(applied.project.tracks.flatMap(\.items).allSatisfy { $0["textStyle"]?.object["color"] == .string("#FFD400") })
    }

    @Test("Two patches in one batch compose; bad selectors are refused")
    func compose() throws {
        let project = try project()
        let ops = try ItemPatch.expand([
            .object(["op": .string("patchItems"), "items": .array([.string("c1")]),
                     "patch": .object(["textStyle": .object(["align": .string("left")])])]),
            .object(["op": .string("patchItems"), "select": .object(["textPreset": .string("bold")]),
                     "patch": .object(["textStyle": .object(["shadow": .object(["blur": .number(4)])])])]),
            .object(["op": .string("patchItems"), "items": .array([.string("c1")]),
                     "patch": .object(["textStyle": .object(["tracking": .number(0.1)])])]),
        ], in: project)
        #expect(ops.count == 3)
        #expect(ops[1].object["item"] == .string("c2"))
        #expect(ops[2].object["patch"]?.object["textStyle"]?.object.keys.sorted() == ["align", "color", "size", "tracking"])
        for bad: JSONValue in [
            .object(["op": .string("patchItems"), "select": .object(["role": .string("x")]), "patch": .object(["a": .integer(1)])]),
            .object(["op": .string("patchItems"), "select": .object(["track": .string("nope")]), "patch": .object(["a": .integer(1)])]),
            .object(["op": .string("patchItems"), "items": .array([.string("c1")])]),
        ] {
            #expect(throws: ProjectError.self) { try ItemPatch.expand([bad], in: project) }
        }
    }

    @Test("Wire setProperties and setProjectProperties merge objects instead of replacing them")
    func wireSetPropertiesMerges() throws {
        var project = try project()
        project["audio"] = .object(["targetLUFS": .number(-14), "normalizeEnabled": .bool(true), "mixGainDb": .number(-2.6)])
        let ops = try ItemPatch.expand([
            .object(["op": .string("setProperties"), "item": .string("c1"),
                     "patch": .object(["textStyle": .object(["strokeWidth": .number(4)])])]),
            .object(["op": .string("setProjectProperties"), "patch": .object(["audio": .object(["mixGainDb": .number(0)])])]),
        ], in: project)
        let applied = try project.applying(.group(label: "Patch", author: .agent, ops: ops.map { try EditOperation(json: $0) })).project
        let style = applied.tracks.flatMap(\.items).first { $0.id == "c1" }?["textStyle"]?.object
        #expect(style?["color"] == .string("#FFFFFF"))
        #expect(style?["strokeWidth"] == .number(4))
        #expect(applied["audio"] == .object(["targetLUFS": .number(-14), "normalizeEnabled": .bool(true), "mixGainDb": .number(0)]))
    }

    @Test("Fields nothing reads are reported with the field they likely meant")
    func unreadFields() throws {
        let warnings = ProjectSchema.unreadFieldWarnings([
            .setProperties(item: "m1", patch: ["volume": .number(0.2), "note": .string("quieter"), "muted": .bool(false)]),
        ])
        #expect(warnings.count == 1)
        #expect(warnings.first?.object["fields"] == .array([.string("volume")]))
        #expect(warnings.first?.object["suggest"]?.object["volume"] == .string("volumeDb"))
        #expect(ProjectSchema.unreadFieldWarnings([.setProperties(item: "m1", patch: ["volumeDb": .number(-6)])]).isEmpty)
    }
}

/// Titles stay off the captions layer, and selects never start or end inside a word (#507).
struct TitleTrackAndWordEdgeTests {
    @Test("Titles go on a Titles text layer, added once, never on Captions")
    func titleTrack() throws {
        var planner = LayerPlanner(Project(name: "Titles"))
        let first = try planner.titleTrack()
        var hook = Item(id: "hook", at: 0, duration: 30)
        hook["text"] = .string("Hook")
        try planner.place(hook, on: first)
        #expect(try planner.titleTrack() == first)
        #expect(planner.project.track(id: first)?.role == TrackRole.titles)
        #expect(planner.project.track(role: TrackRole.captions)?.items.isEmpty == true)
    }

    @Test("Subtitles leave out the titles layer")
    func subtitlesSkipTitles() throws {
        var planner = LayerPlanner(Project(name: "Subtitles"))
        var caption = Item(id: "c", at: 0, duration: 30)
        caption["text"] = .string("spoken")
        try planner.place(caption, on: "t1")
        var hook = Item(id: "h", at: 0, duration: 30)
        hook["text"] = .string("HOOK")
        try planner.place(hook, on: try planner.titleTrack())
        let srt = try SubRip.encode(planner.project)
        #expect(srt.contains("spoken") && !srt.contains("HOOK"))
    }

    @Test("An edge inside a word widens to the word's edge; edges on a gap stay")
    func outsideWords() throws {
        let words: [JSONValue] = [
            .object(["text": .string("xin"), "start": .number(1.0), "end": .number(1.4)]),
            .object(["text": .string("chào"), "start": .number(1.4), "end": .number(2.0)]),
        ]
        let transcript = try JSONDecoder().decode(SourceTranscript.self, from: JSONEncoder().encode(JSONValue.object([
            "version": .integer(1), "key": .string("k"), "language": .string("vi"), "provider": .object([:]),
            "transcribedAt": .string("2026-10-12"), "phrases": .array([]), "words": .array(words),
        ])))
        let widened = transcript.outsideWords(from: 1.2, to: 1.7, slack: 0.034)
        #expect(widened.from == 1.0 && widened.to == 2.0)
        let kept = transcript.outsideWords(from: 0.5, to: 2.5, slack: 0.034)
        #expect(kept.from == 0.5 && kept.to == 2.5)
    }
}
