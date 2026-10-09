import Foundation
import Testing

@testable import BashCutProject

/// The edit as one list: `plan.check` and `plan.apply`.
struct PlanCutTests {
    let transcript = SourceTranscript(
        key: "k", language: "vi", provider: [:], transcribedAt: "",
        phrases: [SubRip.Cue(start: 1.0, end: 1.9, text: "xin chào"), SubRip.Cue(start: 2.0, end: 3.4, text: "các bạn ơi giá năm chục")],
        words: [("xin", 1.0, 1.4), ("chào", 1.4, 1.9), ("các", 2.0, 2.3), ("bạn", 2.3, 2.6), ("ơi", 2.6, 2.8),
                ("giá", 2.8, 3.0), ("năm", 3.0, 3.2), ("chục", 3.2, 3.4)].map {
            CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2)
        })

    /// A 20 s talking clip described as MS 0–8 s, MS 8–12 s, CU 12–20 s, a music file and an empty timeline.
    func project() -> Project {
        var project = ReviewSequenceTests().project()
        for index in project.tracks.indices { project.tracks[index].items = [] }
        project.markers = []
        project.media[0]["hasAudio"] = .bool(true)
        project.media[0]["width"] = .integer(1920)
        project.media[0]["height"] = .integer(1080)
        project.media.append(Media(fields: [
            "id": .string("song"), "path": .string("song.m4a"), "kind": .string("audio"), "fps": FrameRate(48_000, 1).json,
            "frames": .integer(48_000 * 60),
        ]))
        project["plan"] = .object(["sections": .array([.object(["id": .string("hook"), "label": .string("Hook")])])])
        return project
    }

    func spec(_ json: String) throws -> PlanCut.Spec {
        try PlanCut.decode(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test("The list needs clips with one way to pick their range; IDs are unique and titles anchor to a clip")
    func decoding() throws {
        let good = try spec(#"""
            {"clips":[{"media":"m","quote":"giá năm chục"},{"id":"b","media":"m","from":5,"to":7}],
            "titles":[{"text":"Hi","clip":"b","seconds":2}]}
            """#)
        #expect(good.clips.map(\.id) == ["c1", "b"] && good.titles.first?.id == "t1")
        for bad in [
            #"{"clips":[]}"#,
            #"{"clips":[{"media":"m","quote":"a","from":1,"to":2}]}"#,
            #"{"clips":[{"media":"m","from":3,"to":2}]}"#,
            #"{"clips":[{"id":"a","media":"m"},{"id":"a","media":"m"}]}"#,
            #"{"clips":[{"media":"m"}],"titles":[{"text":"x","clip":"nope","seconds":1}]}"#,
            #"{"clips":[{"media":"m"}],"titles":[{"text":"x","seconds":1}]}"#,
        ] {
            #expect(throws: ProjectError.self) { try spec(bad) }
        }
    }

    @Test("Quotes resolve through the transcript; a missing quote is an error, reused source a warning")
    func resolving() throws {
        let project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","quote":"giá năm chục"},{"id":"b","media":"m","quote":"bánh mì"},
            {"id":"c","media":"m","from":2.9,"to":4},{"id":"d","media":"nope","from":0,"to":1}]}
            """#)
        let (clips, problems) = PlanCut.resolve(cut, project: project, transcripts: ["m": transcript])
        #expect(clips.map(\.clip.id) == ["a", "c"])
        #expect(clips[0].from == 2.8 && clips[0].to == 3.4 && clips[0].facts["matched"] == .number(1))
        #expect(clips[1].from == 2.9 && clips[1].to == 4)
        let byID = Dictionary(grouping: problems, by: \.id)
        #expect(byID["quote-not-found"]?.first?.entry == "b" && byID["quote-not-found"]?.first?.severity == "error")
        #expect(byID["unknown-media"]?.first?.entry == "d")
        #expect(byID["source-reused"]?.first?.entry == "c")
        let untranscribed = PlanCut.resolve(cut, project: project, transcripts: [:]).problems
        #expect(untranscribed.contains { $0.id == "no-transcript" && $0.entry == "a" })
    }

    @Test("Apply lays clips in order with sections, titles on their clip and a music bed, all tagged, as one edit")
    func building() throws {
        var project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"section":"hook"},{"id":"b","media":"m","from":5,"to":7,"section":"hook"},
            {"id":"c","media":"m","from":13,"to":17,"section":"body","speed":2}],
            "titles":[{"id":"t","text":"Giá năm chục","clip":"b","offset":0.5,"seconds":1.5,"preset":"pop"}],
            "music":{"media":"song","from":3,"volumeDb":-18}}
            """#)
        let resolved = PlanCut.resolve(cut, project: project, transcripts: [:]).clips
        let built = try PlanCut.build(cut, clips: resolved, on: project)
        let after = built.planner.project
        let main = try #require(after.track(role: TrackRole.main, kind: "video")).items.sorted { $0.at < $1.at }
        #expect(main.map(\.id) == ["plan-a", "plan-b", "plan-c"])
        #expect(main.map(\.at) == [0, 60, 120] && main[2].duration == 60 && main[1].sourceIn == 150)
        #expect(main.allSatisfy { $0.fields[PlanCut.tag] != nil })
        let dialogue = try #require(after.track(role: TrackRole.dialogue, kind: "audio")).items
        #expect(dialogue.count == 3 && dialogue.allSatisfy { $0.fields[PlanCut.tag] != nil })
        #expect(after.sectionMarkers.map(\.id) == ["hook", "body"] && after.sectionMarkers.map(\.at) == [0, 120])
        #expect(after.sectionMarkers.first?.label == "Hook")
        let title = try #require(after.tracks.flatMap(\.items).first { $0.id == "plan-t" })
        #expect(title.at == 75 && title.duration == 45 && title.textPreset == "pop")
        let music = try #require(after.track(role: TrackRole.music)?.items.first)
        #expect(music.duration == 180 && music.fields["volumeDb"] == .number(-18) && music.sourceIn == 48_000 * 3)
        #expect(built.placements.first { $0.id == "c" }?.end == 180)

        // Applying a shorter list replaces only what the last apply built.
        project = try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
        let shorter = try spec(#"{"clips":[{"id":"b","media":"m","from":5,"to":7}]}"#)
        let rebuilt = try PlanCut.build(
            shorter, clips: PlanCut.resolve(shorter, project: project, transcripts: [:]).clips, on: project).planner.project
        #expect(rebuilt.tracks.flatMap(\.items).map(\.id).sorted() == ["plan-b", "plan-b-audio"])
        #expect(rebuilt.sectionMarkers.isEmpty)
    }

    @Test("Apply refuses a Main that holds items it did not build")
    func foreignItems() throws {
        var project = project()
        let index = try #require(project.tracks.firstIndex { $0.role == TrackRole.main })
        project.tracks[index].items = [Item(id: "mine", media: "m", at: 0, duration: 30)]
        let cut = try spec(#"{"clips":[{"media":"m","from":0,"to":1}]}"#)
        #expect(throws: ProjectError.self) {
            try PlanCut.build(cut, clips: PlanCut.resolve(cut, project: project, transcripts: [:]).clips, on: project)
        }
    }

    @Test("Facts per clip: edges, described size, orientation; same media and size back to back is noted")
    func facts() throws {
        var project = project()
        project["format"] = .object(["width": .integer(1080), "height": .integer(1920), "fps": FrameRate(30, 1).json])
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":1,"to":3},{"id":"b","media":"m","from":9,"to":11},{"id":"c","media":"m","from":14,"to":16}],
            "titles":[{"id":"t","text":"Năm chục","at":0,"seconds":2}]}
            """#)
        let resolved = PlanCut.resolve(cut, project: project, transcripts: [:]).clips
        let built = try PlanCut.build(cut, clips: resolved, on: project)
        let facts = PlanCut.facts(cut, clips: resolved, placements: built.placements, on: built.planner.project)
        #expect(facts.clips.count == 3)
        #expect(facts.clips[1].object["described"]?.object["size"] == .string("MS"))
        #expect(facts.clips[0].object["orientation"] == .string("landscape"))
        #expect(facts.problems.filter { $0.id == "same-framing" }.map(\.entry) == ["b"])
        #expect(facts.problems.filter { $0.id == "orientation-mix" }.count == 3)
        #expect(facts.titles.first?.object["charsPerSecond"] == .number(3.5))
    }

    @Test("A covered clip plays its sound on the dialogue layer under muted pictures that fill it in order")
    func covered() throws {
        let project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":6,"cover":[{"media":"m","from":12,"seconds":1},{"media":"m","from":15}]},
            {"id":"b","media":"m","from":12.5,"to":13.5}]}
            """#)
        let (resolved, problems) = PlanCut.resolve(cut, project: project, transcripts: [:])
        #expect(problems.contains { $0.id == "source-reused" && $0.entry == "b" })
        let after = try PlanCut.build(cut, clips: resolved, on: project).planner.project
        let main = try #require(after.track(role: TrackRole.main, kind: "video")).items.sorted { $0.at < $1.at }
        #expect(main.map(\.id) == ["plan-a-cover1", "plan-a-cover2", "plan-b"])
        #expect(main.map(\.at) == [0, 30, 120] && main[1].duration == 90 && main[1].sourceIn == 450)
        #expect(main[0]["muted"] == .bool(true) && main[0].linkedItemID == nil)
        let sound = try #require(after.tracks.flatMap(\.items).first { $0.id == "plan-a-sound" })
        #expect(sound.at == 0 && sound.duration == 120 && sound.sourceIn == 60)
        #expect(throws: ProjectError.self) {
            try spec(#"{"clips":[{"media":"m","from":0,"to":1,"speed":2,"cover":[{"media":"m","from":3}]}]}"#)
        }
    }
}
