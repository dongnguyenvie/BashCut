import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

struct CaptionWordTests {
    @Test("Word timings come from words when they match the text, else from word length")
    func timings() {
        var item = Item(id: "c", at: 100, duration: 60)
        item["text"] = .string("Xin chào\ncác bạn")
        let estimated = item.wordTimings
        #expect(estimated.count == 4)
        #expect(estimated.first?.at == 0)
        #expect(zip(estimated, estimated.dropFirst()).allSatisfy { $0.at < $1.at })
        item["words"] = .array(["Xin", "chào", "các", "bạn"].enumerated().map { index, word in
            .object(["text": .string(word), "at": .integer(index * 10), "dur": .integer(8)])
        })
        #expect(item.wordTimings.map(\.at) == [0, 10, 20, 30])
        #expect(item.spokenWord(at: -1) == nil)
        #expect(item.spokenWord(at: 15) == 1)
        #expect(item.spokenWord(at: 59) == 3)
        // The text was edited: the stored timings no longer fit, so they are estimated again.
        item["text"] = .string("Xin chào mọi người nhé")
        #expect(item.wordTimings.count == 5)
    }

    @Test("Generated captions keep the words heard in each clip, through trim and speed")
    func importWords() throws {
        var clip = Item(id: "a", media: "m", at: 90, duration: 60, sourceIn: 30)
        clip["speed"] = .number(2)
        var project = try Project(name: "Words", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(ProjectFixtures.media("m", path: "m.mov", frames: 900, fps: FrameRate(30, 1), kind: "audio", hasAudio: true)),
            .insert(track: "a1", item: clip),
        ])).project
        // Source 1 s…5 s is heard at frames 90…150 (2× speed).
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nmột hai ba\n"
        let words = [CaptionWords.Timed(text: "một", start: 1.0, end: 1.6), .init(text: "hai", start: 1.6, end: 2.2),
                     .init(text: "ba", start: 2.2, end: 3.0), .init(text: "sau", start: 9, end: 10)]
        project = try project.applying(project.importingSubRip(
            srt, media: "m", words: words, wordStyle: "highlight")).project
        let caption = try #require(project.tracks.filter { $0.kind == "text" }.flatMap(\.items).first)
        #expect(caption.at == 90 && caption.duration == 30)
        #expect(caption.wordStyle == "highlight")
        #expect(caption.wordTimings.map(\.at) == [0, 9, 18])
        #expect(caption["words"]?.array.count == 3)
    }

    @Test("Word timing files decode; bad styles and words are rejected")
    func decodeAndValidate() throws {
        let data = Data(#"[{"text":"Xin","start":0.5,"end":0.8},{"word":" chào","start":0.8,"end":1.1},{"text":"","start":1,"end":2}]"#.utf8)
        #expect(try CaptionWords.decode(data) == [.init(text: "Xin", start: 0.5, end: 0.8), .init(text: "chào", start: 0.8, end: 1.1)])
        #expect(throws: ProjectError.self) { try CaptionWords.decode(Data("{}".utf8)) }
        var item = Item(id: "c", at: 0, duration: 30)
        item["text"] = .string("Xin chào")
        item["wordStyle"] = .string("bounce")
        let project = Project(name: "Bad")
        #expect(throws: ProjectError.self) { try project.applying(.insert(track: "t1", item: item)) }
        item["wordStyle"] = .string("reveal")
        item["words"] = .array([.object(["text": .string("Xin")])])
        #expect(throws: ProjectError.self) { try project.applying(.insert(track: "t1", item: item)) }
        item["words"] = nil
        let placed = try project.applying(.insert(track: "t1", item: item)).project
        let cleared = try placed.applying(.setProperties(item: "c", patch: ["wordStyle": .null])).project
        #expect(cleared.tracks.flatMap(\.items).first?["wordStyle"] == nil)
    }

    @Test("Splitting a caption keeps its words on time")
    func split() throws {
        var item = Item(id: "c", at: 0, duration: 60)
        item["text"] = .string("a b")
        item["words"] = .array([.object(["text": .string("a"), "at": .integer(0), "dur": .integer(20)]),
                                .object(["text": .string("b"), "at": .integer(40), "dur": .integer(20)])])
        let project = try Project(name: "Split").applying(.insert(track: "t1", item: item)).project
        let split = try project.applying(.split(item: "c", atFrame: 30, newID: "d")).project
        let right = try #require(split.tracks.flatMap(\.items).first { $0.id == "d" })
        #expect(right.wordTimings.map(\.at) == [-30, 10])
        #expect(right.spokenWord(at: 5) == 0 && right.spokenWord(at: 10) == 1)
    }
}
