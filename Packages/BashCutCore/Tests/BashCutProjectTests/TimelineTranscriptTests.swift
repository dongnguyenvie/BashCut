import Foundation
import Testing

@testable import BashCutProject

/// Captions and words on the timeline for agents (P0-C1): `captions.export --format json|text`, `transcript.words`.
struct TimelineTranscriptTests {
    /// 30 fps. Media m (audio, 30 fps) is heard on a1 at frames 90…150 from source frame 30 at 2× speed. Caption c1
    /// (frames 90…120) was made from m with transcribed words; c2 (frames 130…190, two lines) has no words; a title on
    /// a text overlay layer starts at 100.
    func project() throws -> Project {
        var clip = Item(id: "clip", media: "m", at: 90, duration: 60, sourceIn: 30)
        clip["speed"] = .number(2)
        var c1 = Item(id: "c1", at: 90, duration: 30)
        c1["text"] = .string("một hai ba")
        c1["captionMedia"] = .string("m")
        c1["words"] = .array([(0, 9), (9, 9), (18, 12)].enumerated().map { index, timing in
            .object(["text": .string(["một", "hai", "ba"][index]), "at": .integer(timing.0), "dur": .integer(timing.1)])
        })
        var c2 = Item(id: "c2", at: 130, duration: 60)
        c2["text"] = .string("Xin chào\ncác bạn")
        var title = Item(id: "title", at: 100, duration: 30)
        title["text"] = .string("Tiêu đề")
        var project = Project(name: "Transcript", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: [
                "id": .string("m"), "kind": .string("audio"), "fps": .array([.integer(30), .integer(1)]),
            ])
        ]
        project.tracks[project.tracks.firstIndex { $0.id == "a1" }!].items = [clip]
        project.tracks[project.tracks.firstIndex { $0.id == "t1" }!].items = [c1, c2]
        project.tracks.append(Track(id: "t2", kind: "text", role: TrackRole.overlay))
        project.tracks[project.tracks.count - 1].items = [title]
        return project
    }

    @Test("JSON cues carry timing, characters per second, gaps and words, in SubRip order")
    func captionsJSON() throws {
        let json = TimelineTranscript.captionsJSON(try project()).object
        let cues = try #require(json["cues"]?.array).map(\.object)
        #expect(cues.map { $0["item"] } == [.string("c1"), .string("title"), .string("c2")])
        #expect(cues.map { $0["index"] } == [.integer(1), .integer(2), .integer(3)])
        #expect(cues[0]["gapBefore"] == nil)
        #expect(cues[1]["gapBefore"] == .integer(-20))
        #expect(cues[2]["gapBefore"] == .integer(0))
        #expect(cues[0]["seconds"] == .number(1))
        #expect(cues[0]["chars"] == .integer(10))
        #expect(cues[0]["cps"] == .number(10))
        #expect(cues[0]["wordTiming"] == .string("transcribed"))
        #expect(cues[0]["captionMedia"] == .string("m"))
        #expect(cues[1]["trackRole"] == .string(TrackRole.overlay))
        #expect(cues[2]["lines"] == .integer(2))
        #expect(cues[2]["chars"] == .integer(16))
        #expect(cues[2]["wordTiming"] == .string("estimated"))
        let words = try #require(cues[0]["words"]?.array).map(\.object)
        #expect(words.map { $0["at"] } == [.integer(90), .integer(99), .integer(108)])
        #expect(words.map { $0["end"] } == [.integer(99), .integer(108), .integer(120)])
    }

    @Test("The text format is one line per cue")
    func captionsText() throws {
        let lines = TimelineTranscript.captionsText(try project()).components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "#1 00:00:03.000–00:00:04.000 1.00s 10.0cps | một hai ba")
        #expect(lines[2] == "#3 00:00:04.333–00:00:06.333 2.00s 8.0cps | Xin chào / các bạn")
    }

    @Test("Words come from caption layers only, with gaps, timing kind and source seconds through the clip")
    func words() throws {
        let json = TimelineTranscript.wordsJSON(try project()).object
        let words = try #require(json["words"]?.array).map(\.object)
        #expect(json["total"] == .integer(7) && json["count"] == .integer(7))
        #expect(words.map { $0["text"]?.string } == ["một", "hai", "ba", "Xin", "chào", "các", "bạn"])
        #expect(!words.contains { $0["item"] == .string("title") })
        #expect(words[0]["timing"] == .string("transcribed") && words[3]["timing"] == .string("estimated"))
        #expect(words[0]["gapBefore"] == nil && words[1]["gapBefore"] == .integer(0))
        #expect(words[3]["gapBefore"] == .integer(10))
        #expect(words[3]["cue"] == .integer(3))
        // Estimated timings round to overlapping frames; each word ends by the next one's start.
        #expect(words[3...].allSatisfy { ($0["gapBefore"]?.int ?? 0) >= 0 })
        // Frame 90 is source second 1; at 2× speed frames 99…108 are source seconds 1.6…2.2.
        let source = try #require(words[1]["source"]?.object)
        #expect(source["media"] == .string("m") && source["clip"] == .string("clip"))
        #expect(source["start"] == .number(1.6) && source["end"] == .number(2.2))
        // c2 was not made from a media: no source field at all.
        #expect(words[3]["source"] == nil)
    }

    @Test("A caption whose clip moved away has a null source; from/to and media filter")
    func filtersAndDrift() throws {
        var project = try project()
        let audio = project.tracks.firstIndex { $0.id == "a1" }!
        project.tracks[audio].items[0].at = 400
        let all = try #require(TimelineTranscript.wordsJSON(project).object["words"]?.array).map(\.object)
        #expect(all[0]["source"] == .null)
        let window = TimelineTranscript.wordsJSON(project, from: 100, to: 140).object
        #expect(window["words"]?.array.compactMap { $0.object["text"]?.string } == ["hai", "ba", "Xin"])
        #expect(window["total"] == .integer(7))
        let fromMedia = TimelineTranscript.wordsJSON(project, media: "m").object
        #expect(fromMedia["count"] == .integer(3))
    }

    @Test("A split caption only reports the words timed inside each half")
    func split() throws {
        var item = Item(id: "c", at: 0, duration: 60)
        item["text"] = .string("a b")
        item["words"] = .array([.object(["text": .string("a"), "at": .integer(0), "dur": .integer(20)]),
                                .object(["text": .string("b"), "at": .integer(40), "dur": .integer(20)])])
        let project = try Project(name: "Split").applying(.insert(track: "t1", item: item)).project
        let split = try project.applying(.split(item: "c", atFrame: 30, newID: "d")).project
        let words = try #require(TimelineTranscript.wordsJSON(split).object["words"]?.array).map(\.object)
        #expect(words.map { $0["text"]?.string } == ["a", "b"])
        #expect(words.map { $0["item"]?.string } == ["c", "d"])
    }
}
