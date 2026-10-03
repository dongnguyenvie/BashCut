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

    @Test("Long transcripts attach the same words as scanning every word for every cue")
    func longTranscript() throws {
        // 300 cues of 1.2 s with 4 words each; a ramped, trimmed clip and the timeline path.
        let words = (0..<1200).map { index in
            CaptionWords.Timed(text: "w\(index)", start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.27)
        }
        let cues = (0..<300).map { SubRip.Cue(start: Double($0) * 1.2, end: Double($0) * 1.2 + 1.1, text: "cue \($0)") }
        var clip = Item(id: "a", media: "m", at: 45, duration: 9_000, sourceIn: 37)
        clip["speed"] = .number(1.5)
        let project = try Project(name: "Words", fps: FrameRate(30_000, 1_001)).applying(.group(
            label: "Setup", author: .user, ops: [
                .addMedia(ProjectFixtures.media(
                    "m", path: "m.mov", frames: 30_000, fps: FrameRate(30, 1), kind: "audio", hasAudio: true)),
                .insert(track: "a1", item: clip),
            ])).project
        let clips = project.audibleClips("m")
        var expected: [Item] = []
        for (clip, asset) in clips {
            let sourceStart = Double(clip.sourceIn) / asset.fps.value
            let sourceEnd = sourceStart + clip.sourceSeconds(afterFrames: clip.duration, fps: project.fps)
            for cue in cues where cue.end > sourceStart && cue.start < sourceEnd {
                let frame = { (seconds: Double) in
                    clip.at + Int(clip.timelineFrames(atSourceSeconds: seconds - sourceStart, fps: project.fps).rounded())
                }
                let at = max(clip.at, frame(max(cue.start, sourceStart)))
                let end = min(clip.end, frame(min(cue.end, sourceEnd)))
                guard end > at else { continue }
                let heard = words.filter { $0.end > sourceStart && $0.start < sourceEnd }
                expected.append(SubRip.caption(cue.text, at: at, duration: end - at).attachingWords(heard) {
                    frame(min(max($0, sourceStart), sourceEnd))
                })
            }
        }
        let placed = project.placedCues(cues, in: clips, words: words)
        #expect(placed.count == expected.count && placed.count > 100)
        #expect(placed.map { $0["words"] } == expected.map { $0["words"] })
        #expect(placed.allSatisfy { $0["words"] != nil })

        let srt = cues.enumerated().map { index, cue in
            func stamp(_ seconds: Double) -> String {
                let ms = Int((seconds * 1000).rounded())
                return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
            }
            return "\(index + 1)\n\(stamp(cue.start)) --> \(stamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
        let imported = try project.applying(project.importingSubRip(srt, words: words)).project
        let captions = imported.tracks.filter { $0.kind == "text" }.flatMap(\.items).sorted { $0.at < $1.at }
        let reference = try SubRip.decode(srt, fps: project.fps).map { item in
            item.attachingWords(words) { Int(($0 * project.fps.value).rounded()) }
        }.sorted { $0.at < $1.at }
        #expect(captions.count == reference.count)
        #expect(captions.map { $0["words"] } == reference.map { $0["words"] })
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
