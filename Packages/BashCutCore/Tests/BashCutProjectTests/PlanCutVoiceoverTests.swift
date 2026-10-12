import Foundation
import Testing

@testable import BashCutProject

/// `plan.cut` for an edit made of voiceover lines and graphics (an explainer): lines play one after another on the
/// Voiceover layer, graphics fill spans anchored to lines and sections, captions take each line's own text.
struct PlanCutVoiceoverTests {
    /// Two kept takes (2 s and 3 s) as media the build adds, two rendered graphics (4 s and 10 s) and a music file.
    func project() -> Project {
        var project = Project(name: "Explainer", fps: FrameRate(30, 1), contentLanguage: "vi")
        project.media = [
            Media(fields: [
                "id": .string("card"), "path": .string("card.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
                "frames": .integer(120), "alpha": .bool(true),
            ]),
            Media(fields: [
                "id": .string("map"), "path": .string("map.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
                "frames": .integer(300),
            ]),
        ]
        project["plan"] = .object(["sections": .array([.object(["id": .string("p1"), "label": .string("Phần 1")])])])
        return project
    }

    func take(_ id: String, seconds: Int, words: [(String, Double, Double)]) -> PlanCut.LineTake {
        PlanCut.LineTake(
            media: Media(fields: [
                "id": .string(id), "path": .string("voiceover/generated/x/\(id).wav"), "kind": .string("audio"),
                "fps": FrameRate(30, 1).json, "frames": .integer(seconds * 30),
            ]),
            voice: ["text": .string("text")],
            words: words.map { CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2) })
    }

    var takes: [String: PlanCut.LineTake] {
        [
            "l1": take("t1", seconds: 2, words: [("xin", 0.1, 0.5), ("chào", 0.5, 1.0)]),
            "l2": take("t2", seconds: 3, words: [("ba", 0.2, 0.6), ("cây", 0.6, 1.0), ("số", 1.0, 1.5)]),
        ]
    }

    func spec(_ json: String) throws -> PlanCut.Spec {
        try PlanCut.decode(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test("A list may hold lines without clips; graphics need one anchor and a known entry")
    func decoding() throws {
        let good = try spec(#"""
            {"voiceover":[{"text":"Xin chào","section":"p1"},{"id":"l2","text":"Ba cây số","pause":0.5}],
             "graphics":[{"media":"card","on":"l1"},{"id":"bg","media":"map","section":"p1","track":"main","render":{"x":1}}]}
            """#)
        #expect(good.voiceover.map(\.id) == ["l1", "l2"] && good.voiceover[1].pause == 0.5)
        #expect(good.graphics.map(\.id) == ["g1", "bg"] && good.graphics[1].main)
        #expect(good.unknownFields.isEmpty, "render is a plugin's, not an unknown field")
        for bad in [
            #"{"voiceover":[]}"#,
            #"{"voiceover":[{"text":""}]}"#,
            #"{"voiceover":[{"text":"a"}],"graphics":[{"media":"card"}]}"#,
            #"{"voiceover":[{"text":"a"}],"graphics":[{"media":"card","on":"nope"}]}"#,
            #"{"voiceover":[{"text":"a"}],"graphics":[{"media":"card","at":1}]}"#,
            #"{"voiceover":[{"text":"a"}],"graphics":[{"media":"card","on":"l1","track":"top"}]}"#,
        ] {
            #expect(throws: ProjectError.self) { try spec(bad) }
        }
    }

    @Test("Lines play back to back with their pauses; graphics fill their spans, cut to what the movie has")
    func building() throws {
        let cut = try spec(#"""
            {"voiceover":[{"id":"l1","text":"Xin chào","section":"p1","pause":0.5},
             {"id":"l2","text":"Ba cây số","caption":"3 cây số","section":"p2"}],
             "graphics":[{"id":"bg","media":"map","at":0,"until":"l2","track":"main"},{"id":"g1","media":"card","on":"l2","offset":0.5}],
             "titles":[{"id":"t1","text":"Ba cây số","clip":"l2","seconds":1}],
             "captions":{"from":"speech"}}
            """#)
        let built = try PlanCut.build(cut, clips: [], on: project(), takes: takes)
        let after = built.planner.project
        let items = Dictionary(uniqueKeysWithValues: after.tracks.flatMap(\.items).compactMap { item in
            item.fields[PlanCut.tag]?.string.map { ($0 == "captions" ? item.id : $0, item) }
        })
        #expect(items["l1"]?.at == 0 && items["l1"]?.duration == 60)
        #expect(items["l2"]?.at == 75, "2 s line + 0.5 s pause")
        #expect(after.track(role: TrackRole.voiceover)?.items.count == 2)
        #expect(after.media.contains { $0.id == "t1" } && after.media.contains { $0.id == "t2" }, "takes added as media")
        #expect(items["bg"]?.at == 0 && items["bg"]?.duration == 165, "map until the end of l2 (75 + 90)")
        #expect(after.track(role: TrackRole.main)?.items.first?.id == "plan-bg")
        let card = try #require(items["g1"])
        #expect(card.at == 90 && card.duration == 75, "0.5 s into l2, to its end")
        #expect(after.tracks.first { $0.items.contains { $0.id == card.id } }?.role == TrackRole.overlay)
        #expect(items["t1"]?.at == 75)
        #expect(after.sectionMarkers.map(\.id) == ["p1", "p2"] && after.sectionMarkers[1].at == 75)
        #expect(after.sectionMarkers.first?.label == "Phần 1")
        let cues = after.tracks.filter { $0.role == TrackRole.captions }.flatMap(\.items)
        #expect(cues.map(\.text) == ["Xin chào", "3 cây số"], "each line's own text, or its caption")
        #expect(cues.last?.at == 75 + 6, "timed by the take's first word (0.2 s)")
    }

    @Test("Caption lines break at word gaps under maxChars, early after punctuation")
    func captionLines() throws {
        #expect(PlanCut.captionLines("Hồ Tây rộng năm trăm hai mươi tám héc ta, gấp gần năm mươi lần Hồ Gươm.", maxChars: 24)
            == "Hồ Tây rộng năm trăm hai\nmươi tám héc ta,\ngấp gần năm mươi lần Hồ\nGươm.")
        #expect(PlanCut.captionLines("Ngắn thôi", maxChars: 24) == "Ngắn thôi")
        let tooShort = #"{"voiceover":[{"text":"a"}],"captions":{"maxChars":3}}"#
        #expect(throws: ProjectError.self) { try PlanCut.decode(JSONDecoder().decode(JSONValue.self, from: Data(tooShort.utf8))) }
    }

    @Test("Check facts: a line without a take, a graphic without media or shorter than its span, black on Main")
    func facts() throws {
        let cut = try spec(#"""
            {"voiceover":[{"id":"l1","text":"Xin chào"},{"id":"l2","text":"Ba cây số"},{"id":"l3","text":"Bốn"}],
             "graphics":[{"id":"bg","media":"card","on":"l1","until":"l2","track":"main"},{"id":"g1","on":"l2"}]}
            """#)
        let project = project()
        let built = try PlanCut.build(cut, clips: [], on: project, takes: takes)
        let facts = PlanCut.lineAndGraphicFacts(cut, takes: takes, placements: built.placements, on: built.planner.project)
        let problems = Dictionary(grouping: facts.problems, by: \.id)
        #expect(problems["no-take"]?.map(\.entry) == ["l3"])
        #expect(problems["graphic-no-media"]?.map(\.entry) == ["g1"])
        #expect(problems["graphic-short"]?.map(\.entry) == ["bg"], "a 4 s card over a 5 s span")
        let graphics = facts.graphics.map(\.object)
        #expect(graphics[1]["at"] == .number(2) && graphics[1]["seconds"] == .number(3), "g1's span before it is rendered")
        #expect(graphics[0]["short"] == .number(5))
        #expect(problems["picture-gap"] != nil, "Main is black after the card")
    }
}
