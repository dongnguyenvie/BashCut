import Foundation
import Testing

@testable import BashCutProject

/// What was said in a source media, in its own seconds (P0-A2): `media.transcript`, `transcript.words --heard`.
struct SourceTranscriptTests {
    func transcript() -> SourceTranscript {
        SourceTranscript(
            key: "k", language: "vi", provider: ["plugin": .string("test"), "provider": .string("test.w")],
            transcribedAt: "2026-10-07T00:00:00Z",
            phrases: [
                .init(start: 3.0, end: 3.4, text: "ba"),
                .init(start: 0.2, end: 1.5, text: "một hai"),
                .init(start: 6.0, end: 6.5, text: "bốn"),
            ],
            words: [
                .init(text: "hai", start: 1.0, end: 1.5, confidence: 0.9, speaker: "A"),
                .init(text: "một", start: 0.2, end: 0.5, confidence: 0.5),
                .init(text: "ba", start: 3.0, end: 3.4, noSpeechProb: 0.1),
                .init(text: "bốn", start: 6.0, end: 6.5),
            ])
    }

    @Test("Phrases and words read in source seconds, with gaps, confidence and precision flags")
    func reading() throws {
        let record = transcript()
        #expect(record.phrases.map(\.text) == ["một hai", "ba", "bốn"])
        #expect(abs(record.speechSeconds - 2.2) < 1e-9)
        let overview = record.overviewJSON.object
        #expect(overview["firstSpeech"] == .number(0.2))
        #expect(overview["lastSpeech"] == .number(6.5))
        let precision = try #require(overview["precision"]).object
        #expect(precision["wordTimes"] == .string("provider"))
        #expect(precision["confidence"] == .bool(true))
        #expect(precision["speakers"] == .bool(true))
        #expect(precision["events"] == .bool(false))

        let phrases = try #require(record.json(.phrases).object["phraseList"]?.array).map(\.object)
        #expect(phrases.map { $0["words"] } == [.integer(2), .integer(1), .integer(1)])
        #expect(phrases[0]["confidence"] == .number(0.7))
        #expect(phrases[1]["confidence"] == .null)
        #expect(phrases[1]["gapBefore"] == .number(1.5))
        #expect(record.json(.phrases).object["wordList"] == nil)

        let words = try #require(record.json(.words, from: 0.8, to: 3.2).object["wordList"]?.array).map(\.object)
        #expect(words.map { $0["text"] } == [.string("hai"), .string("ba")])
        #expect(words[0]["speaker"] == .string("A"))
        #expect(words[0]["gapBefore"] == .number(0.5))
        #expect(words[1]["noSpeechProb"] == .number(0.1))
        #expect(words[1]["confidence"] == nil)

        let text = try #require(record.json(.text, from: 2).string)
        #expect(text == "#2 00:00:03.000–00:00:03.400 0.40s | ba\n#3 00:00:06.000–00:00:06.500 0.50s | bốn")
    }

    @Test("A stored transcript round-trips through JSON")
    func coding() throws {
        let record = transcript()
        let decoded = try JSONDecoder().decode(SourceTranscript.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.version == SourceTranscript.version)
    }

    @Test("Provider word facts decode; values out of range are left out")
    func providerFacts() throws {
        let data = Data(#"""
        [{"text":"Xin","start":0.5,"end":0.8,"probability":0.8,"speaker":" S1 ","noSpeechProb":0.2},
         {"word":"chào","start":0.8,"end":1.1,"confidence":1.5,"event":"","noSpeechProb":-1},
         {"text":"[cười]","start":1.1,"end":1.6,"event":"laughter"}]
        """#.utf8)
        #expect(try CaptionWords.decode(data) == [
            .init(text: "Xin", start: 0.5, end: 0.8, confidence: 0.8, speaker: "S1", noSpeechProb: 0.2),
            .init(text: "chào", start: 0.8, end: 1.1),
            .init(text: "[cười]", start: 1.1, end: 1.6, event: "laughter"),
        ])
    }

    @Test("Heard words follow the clips that play the media now, through trim and speed")
    func heardWords() throws {
        // 30 fps; the clip plays source 1…5 s of m at 2× on frames 90…150.
        var clip = Item(id: "clip", media: "m", at: 90, duration: 60, sourceIn: 30)
        clip["speed"] = .number(2)
        var muted = Item(id: "muted", media: "m", at: 200, duration: 60)
        muted["muted"] = .bool(true)
        var project = Project(name: "Heard", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: ["id": .string("m"), "kind": .string("audio"), "fps": .array([.integer(30), .integer(1)])])
        ]
        project.tracks[project.tracks.firstIndex { $0.id == "a1" }!].items = [clip, muted]

        let json = TimelineTranscript.heardWordsJSON(project, transcripts: ["m": transcript()]).object
        let words = try #require(json["words"]?.array).map(\.object)
        #expect(words.map { $0["text"] } == [.string("hai"), .string("ba")])
        #expect(words.map { $0["at"] } == [.integer(90), .integer(120)])
        #expect(words.map { $0["end"] } == [.integer(98), .integer(126)])
        #expect(words[0]["item"] == .string("clip"))
        #expect(words[0]["timing"] == .string("source"))
        #expect(words[0]["confidence"] == .number(0.9))
        #expect(words[0]["source"]?.object["start"] == .number(1))
        #expect(words[1]["gapBefore"] == .integer(22))
        #expect(json["total"] == .integer(2))

        let late = TimelineTranscript.heardWordsJSON(project, transcripts: ["m": transcript()], from: 100).object
        #expect(late["count"] == .integer(1))
        #expect(TimelineTranscript.heardWordsJSON(project, transcripts: ["m": transcript()], media: "x")
            .object["count"] == .integer(0))
    }

    @Test("Stored phrases import like the same SubRip text")
    func importingCues() throws {
        let project = Project(name: "Cues", fps: FrameRate(30, 1))
        let record = transcript()
        let srt = "1\n00:00:00,200 --> 00:00:01,500\nmột hai\n\n2\n00:00:03,000 --> 00:00:03,400\nba\n\n"
            + "3\n00:00:06,000 --> 00:00:06,500\nbốn\n"
        let fromText = try project.applying(project.importingSubRip(srt, words: record.words)).project
        let fromCues = try project.applying(project.importingCues(record.phrases, words: record.words)).project
        let texts = { (project: Project) in
            project.tracks.first { $0.role == TrackRole.captions }?.items.map {
                [JSONValue.string($0.text), .integer($0.at), $0["words"] ?? .null]
            }
        }
        #expect(texts(fromCues) == texts(fromText))
        #expect(texts(fromCues)?.count == 3)
    }
}
