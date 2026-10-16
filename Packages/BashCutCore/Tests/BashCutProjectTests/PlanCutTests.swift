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

    @Test("The list needs clips with one way to pick their range (from/to may move a quote's edges); IDs are unique and titles anchor to a clip")
    func decoding() throws {
        let good = try spec(#"""
            {"clips":[{"media":"m","quote":"giá năm chục"},{"id":"b","media":"m","from":5,"to":7}],
            "titles":[{"text":"Hi","clip":"b","seconds":2}]}
            """#)
        #expect(good.clips.map(\.id) == ["c1", "b"] && good.titles.first?.id == "t1")
        for bad in [
            #"{"clips":[]}"#,
            #"{"clips":[{"media":"m","quote":"a","words":"1-2"}]}"#,
            #"{"clips":[{"media":"m","quote":"a","from":2,"to":1}]}"#,
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
        #expect(clips[1].from == 2.8 && clips[1].to == 4, "2.9 s cut into “giá” (2.8–3.0 s)")
        let byID = Dictionary(grouping: problems, by: \.id)
        #expect(byID["quote-not-found"]?.first?.entry == "b" && byID["quote-not-found"]?.first?.severity == "error")
        #expect(byID["unknown-media"]?.first?.entry == "d")
        #expect(byID["source-reused"]?.first?.entry == "c")
        let untranscribed = PlanCut.resolve(cut, project: project, transcripts: [:]).problems
        #expect(untranscribed.contains { $0.id == "no-transcript" && $0.entry == "a" })
    }

    @Test("A title on a section starts with its first clip and, without seconds, lasts to the section's end")
    func sectionTitles() throws {
        let project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"section":"hook"},{"id":"b","media":"m","from":5,"to":7,"section":"body"},
            {"id":"c","media":"m","from":13,"to":15,"section":"body"}],
            "titles":[{"id":"t","text":"Thân bài","section":"body","offset":0.5},{"id":"u","text":"Clip","clip":"a"}]}
            """#)
        let built = try PlanCut.build(cut, clips: PlanCut.resolve(cut, project: project, transcripts: [:]).clips, on: project)
        let items = built.planner.project.tracks.flatMap(\.items)
        let section = try #require(items.first { $0.id == "plan-t" })
        let clip = try #require(items.first { $0.id == "plan-u" })
        #expect(section.at == 75 && section.end == 180)
        #expect(clip.at == 0 && clip.end == 60)
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m","section":"x"}],"titles":[{"text":"y","at":1}]}"#) }
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m"}],"titles":[{"text":"y","section":"nope"}]}"#) }
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

    @Test("A title takes a library preset's look by ID; style fields go into textStyle over it")
    func titleLooks() throws {
        let project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":0,"to":4}],
            "titles":[{"id":"t","text":"BẮT HEO","clip":"a","seconds":2,"preset":"stacked-keyword",
            "style":{"stroke":"#000000","strokeWidth":8,"opacity":0.9}},
            {"id":"u","text":"Nhãn","at":1,"seconds":1,"preset":"bold-outline","style":{"textStyle":{"size":0.05}}}]}
            """#)
        #expect(cut.titles[0].textStyle["strokeWidth"] == .integer(8) && cut.titles[0].style["opacity"] == .number(0.9))
        let template = try #require(LibraryBuiltIns.textTemplates.first { $0.id == "stacked-keyword" })
        let built = try PlanCut.build(
            cut, clips: PlanCut.resolve(cut, project: project, transcripts: [:]).clips, on: project,
            textPresets: ["stacked-keyword": try LibraryTextPreset(params: template.params)])
        let items = built.planner.project.tracks.flatMap(\.items)
        let title = try #require(items.first { $0.id == "plan-t" })
        let style = title["textStyle"]?.object ?? [:]
        #expect(title.textPreset == "hook-title" && style["font"] == .string("System-CondensedBlack"))
        #expect(style["strokeWidth"] == .integer(8) && style["uppercase"] == .bool(true))
        #expect(title["opacity"] == .number(0.9))
        let label = try #require(items.first { $0.id == "plan-u" })
        #expect(label.textPreset == "bold-outline" && label["textStyle"]?.object["size"] == .number(0.05))
    }

    @Test("Captions come from the transcript through the built clips, in their style; speech clips are tagged, music ducks")
    func captionsAndMix() throws {
        var project = project()
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","quote":"giá năm chục"},{"id":"b","media":"m","from":8,"to":10,"role":"broll"}],
            "captions":{"from":"speech","preset":"bold-outline","style":{"size":0.05,"positionY":0.2},
                        "replace":{"năm chục":"50"}},
            "music":{"media":"song","duckDb":-20}}
            """#)
        let resolved = PlanCut.resolve(cut, project: project, transcripts: ["m": transcript]).clips
        let built = try PlanCut.build(cut, clips: resolved, on: project, transcripts: ["m": transcript])
        let after = built.planner.project
        let items = after.tracks.flatMap(\.items)
        let cues = items.filter { $0.fields[PlanCut.tag] == .string("captions") }
        // Only the quoted words (2.8–3.4 s) play, so one cue, cut to them, at the clip's start.
        #expect(cues.count == 1 && cues[0].at == 0 && cues[0].textPreset == "bold-outline")
        // Its text is the words heard, not the whole phrase, with the transcript's slip replaced.
        #expect(cues[0].text == "giá 50")
        #expect(cues[0]["textStyle"]?.object["size"] == .number(0.05) && cues[0]["captionMedia"] == .string("m"))
        #expect(items.first { $0.id == "plan-a" }?["tag"]?.object["role"] == .string("speech"))
        #expect(items.first { $0.id == "plan-b" }?["tag"]?.object["role"] == .string("broll"))
        #expect(after.track(role: TrackRole.music)?["duckUnderSpeechDb"] == .number(-20))

        // Applying again replaces the captions it made instead of adding more.
        project = try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
        let again = try PlanCut.build(cut, clips: resolved, on: project, transcripts: ["m": transcript]).planner.project
        #expect(again.tracks.flatMap(\.items).filter { $0.fields[PlanCut.tag] == .string("captions") }.count == 1)
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m"}],"captions":{"from":"script"}}"#) }
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

    @Test("A patch names only what changes: entries by ID merge, null removes, unknown IDs are added")
    func patch() throws {
        let list = JSONValue.object([
            "clips": .array([
                .object(["id": .string("c1"), "media": .string("m"), "from": .number(0), "to": .number(2)]),
                .object(["id": .string("c2"), "media": .string("m"), "quote": .string("xin chào"),
                         "cover": .array([.object(["media": .string("m"), "from": .number(5)])])]),
            ]),
            "titles": .array([.object(["id": .string("t1"), "text": .string("Hook"), "style": .object(["size": .number(0.05)])])]),
            "music": .object(["media": .string("song"), "volumeDb": .number(-18)]),
        ])
        let patched = try PlanCut.patch(list, with: .object([
            "clips": .object([
                "c1": .null,
                "c2": .object(["cover": .array([.object(["media": .string("m"), "from": .number(9)])])]),
                "c3": .object(["media": .string("m"), "from": .number(10), "to": .number(11), "speed": .null]),
            ]),
            "titles": .object(["t1": .object(["style": .object(["background": .object(["opacity": .number(0.6)])])])]),
            "music": .null,
        ]))
        let clips = patched.object["clips"]?.array ?? []
        #expect(clips.map { $0.object["id"]?.string } == ["c2", "c3"])
        #expect(clips[0].object["quote"] == .string("xin chào"), "untouched fields stay")
        #expect(clips[0].object["cover"]?.array.first?.object["from"] == .number(9), "a list inside an entry is replaced")
        #expect(clips[1].object["speed"] == nil, "null is never stored")
        let style = patched.object["titles"]?.array.first?.object["style"]?.object
        #expect(style?["size"] == .number(0.05) && style?["background"]?.object["opacity"] == .number(0.6))
        #expect(patched.object["music"] == nil)
        #expect(throws: ProjectError.self) { try PlanCut.patch(list, with: .array([])) }
    }

    @Test("A clip's in edge rounds down and its out edge up to whole frames, so it keeps its last word whole")
    func wholeFrames() throws {
        let cut = try spec(#"{"clips":[{"id":"a","media":"m","from":1.02,"to":1.88}]}"#)
        let built = try PlanCut.build(cut, clips: PlanCut.resolve(cut, project: project(), transcripts: [:]).clips, on: project())
        let clip = try #require(built.planner.project.track(role: TrackRole.main, kind: "video")?.items.first)
        #expect(clip.sourceIn == 30 && clip.duration == 27)
    }

    @Test("A clip's or cover's zoom, pan and tilt frame its picture; fields nothing reads are warned about")
    func framing() throws {
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"zoom":1.2,"why":"punch-in"},
            {"id":"b","media":"m","from":5,"to":7,"scale":2,"cover":[{"media":"m","from":13,"tilt":-40,"blur":1}]}],
            "titles":[{"id":"t","text":"Hi","clip":"a","postion":0.8}]}
            """#)
        let built = try PlanCut.build(cut, clips: PlanCut.resolve(cut, project: project(), transcripts: [:]).clips, on: project())
        let items = built.planner.project.tracks.flatMap(\.items)
        #expect(items.first { $0.id == "plan-a" }?["transform"]?.object["zoom"] == .number(1.2))
        #expect(items.first { $0.id == "plan-a" }?.linkedItemID.flatMap { id in items.first { $0.id == id } }?["transform"] == nil)
        #expect(items.first { $0.id == "plan-b-cover1" }?["transform"]?.object["tilt"] == .number(-40))
        let warned = PlanCut.resolve(cut, project: project(), transcripts: [:]).problems.filter { $0.id == "unknown-field" }
        #expect(warned.map { $0.entry ?? "" } == ["b", "b", "t"])
        #expect(warned.map { $0.facts["fields"] } == [.array([.string("scale")]), .array([.string("blur")]), .array([.string("postion")])])
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m","from":0,"to":1,"zoom":0}]}"#) }
    }

    @Test("from or to on a quote moves that edge (snapped out of words); a patched quote drops the old edges")
    func quoteEdges() throws {
        let cut = try spec(#"{"clips":[{"id":"a","media":"m","quote":"các bạn ơi","to":3.1}]}"#)
        let clip = try #require(PlanCut.resolve(cut, project: project(), transcripts: ["m": transcript]).clips.first)
        #expect(clip.from == 2.0 && clip.to == 3.2)
        #expect(clip.facts["quoted"]?.object["to"] == .number(2.8))
        let list = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"clips":[{"id":"a","media":"m","quote":"xin","to":3.1}]}"#.utf8))
        let patched = try PlanCut.patch(list, with: .object(["clips": .object(["a": .object(["quote": .string("giá năm chục")])])]))
        #expect(patched.object["clips"]?.array.first?.object["to"] == nil)
        let moved = try PlanCut.patch(list, with: .object(["clips": .object(["a": .object(["from": .number(0.9)])])]))
        #expect(moved.object["clips"]?.array.first?.object["quote"] == .string("xin"))
    }

    @Test("Sound effects go on the SFX layer at a clip's or title's start plus offset, clipped to the edit")
    func soundEffects() throws {
        let cut = try spec(#"""
            {"clips":[{"id":"a","media":"m","from":0,"to":2,"section":"hook"},{"id":"b","media":"m","from":5,"to":7}],
            "titles":[{"id":"t","text":"Hi","clip":"b","offset":0.5,"seconds":1}],
            "sfx":[{"id":"w","media":"song","on":"b","offset":-0.2,"seconds":0.5,"volumeDb":-6},
                   {"media":"song","on":"t","seconds":0.3},{"media":"song","at":3.9,"seconds":2,"pitch":1}]}
            """#)
        let resolved = PlanCut.resolve(cut, project: project(), transcripts: [:])
        #expect(resolved.problems.contains { $0.id == "unknown-field" && $0.entry == "s3" })
        let built = try PlanCut.build(cut, clips: resolved.clips, on: project()).planner.project
        let sfx = try #require(built.track(role: TrackRole.sfx)).items.sorted { $0.at < $1.at }
        #expect(sfx.map(\.id) == ["plan-w", "plan-s2", "plan-s3"])
        #expect(sfx.map(\.at) == [54, 75, 117] && sfx.map(\.duration) == [15, 9, 3])
        #expect(sfx[0].fields["volumeDb"] == .number(-6) && sfx[0].fields[PlanCut.tag] == .string("w"))
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m","from":0,"to":1}],"sfx":[{"media":"song","on":"nope"}]}"#) }
    }

    @Test("Review limits ride with the list as an object")
    func reviewLimits() throws {
        let limits = try spec(#"{"clips":[{"media":"m","from":0,"to":1}],"review":{"minTextSize":0.04}}"#).review
        #expect(limits?["minTextSize"] == .number(0.04))
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m","from":0,"to":1}],"review":3}"#) }
    }

    @Test("Rough seconds that cut into a word move out to its edges; the times given stay as requested")
    func roughSecondsSnap() throws {
        let cut = try spec(#"{"clips":[{"media":"m","from":2.1,"to":3.1}]}"#)
        let clip = try #require(PlanCut.resolve(cut, project: project(), transcripts: ["m": transcript]).clips.first)
        #expect(clip.from == 2.0 && clip.to == 3.2)
        #expect(clip.facts["requested"]?.object["from"] == .number(2.1))
        // An edge within a frame of the word's far edge stays out of the word instead of taking it whole.
        let nudged = try spec(#"{"clips":[{"media":"m","from":1.89,"to":2.31}]}"#)
        let near = try #require(PlanCut.resolve(nudged, project: project(), transcripts: ["m": transcript]).clips.first)
        #expect(near.from == 1.9 && near.to == 2.3)
        let clean = try spec(#"{"clips":[{"media":"m","from":2.0,"to":3.2}]}"#)
        let kept = try #require(PlanCut.resolve(clean, project: project(), transcripts: ["m": transcript]).clips.first)
        #expect(kept.from == 2.0 && kept.facts["requested"] == nil)
        // Seconds holding transcribed words play speech, like a quote; silent seconds keep no role.
        #expect(kept.clip.role == "speech")
        let silent = try spec(#"{"clips":[{"media":"m","from":10,"to":12}]}"#)
        #expect(PlanCut.resolve(silent, project: project(), transcripts: ["m": transcript]).clips.first?.clip.role == nil)
    }

    @Test("Entries cite fact keys with facts: [key]; plan check warns for a key that is no fact or claim")
    func factReferences() throws {
        let cited = try spec(#"""
            {"clips":[{"media":"m","from":0,"to":2,"facts":["price-pho"]}],
            "voiceover":[{"id":"v1","text":"528 ha","facts":["area","nope"]}],
            "titles":[{"text":"50k","clip":"c1","seconds":1,"facts":[]}]}
            """#)
        #expect(cited.unknownFields.isEmpty)
        #expect(cited.factReferences.map(\.entry) == ["c1", "v1"])
        let problems = PlanCut.factProblems(cited, known: ["price-pho", "area", "nope"])
        #expect(problems.isEmpty)
        let missing = PlanCut.factProblems(cited, known: ["area", "nope"])
        #expect(missing.map(\.entry) == ["c1"] && missing.first?.id == "unknown-fact")
        #expect(PlanCut.factProblems(cited, known: [])[1].facts["keys"] == .array([.string("area"), .string("nope")]))
        #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m","facts":"price"}]}"#) }
    }
}
