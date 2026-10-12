import Foundation
import Testing

@testable import BashCutProject

/// Speech, script and voice tools (P0-C2, C3, C5, C8, C9): units, alignment, rate, narration windows, grouping.
struct SpeechToolsTests {
    @Test("Units follow the language: Vietnamese syllables, CJK characters, else words")
    func units() {
        #expect(SpeechUnits.unit(for: "vi") == .syllables && SpeechUnits.unit(for: "zh-Hans") == .characters)
        #expect(SpeechUnits.unit(for: "en") == .words)
        #expect(SpeechUnits.count("Xin chào các bạn, hôm nay!", unit: .syllables) == 6)
        #expect(SpeechUnits.count("你好世界", unit: .characters) == 4)
        #expect(SpeechUnits.tokens("— chào ... bạn!") == ["chào", "bạn"])
    }

    func heard(_ text: String, start: Double = 0, step: Double = 0.5) -> [CaptionWords.Timed] {
        text.split(separator: " ").enumerated().map { index, word in
            CaptionWords.Timed(text: String(word), start: start + Double(index) * step, end: start + Double(index) * step + 0.4)
        }
    }

    @Test("Alignment marks matched, substituted and missing words and leftover heard words")
    func alignment() {
        let result = TextAlignment.align("Xin chào các bạn thân mến", to: heard("xin chao các bạn mến nhé"))
        #expect(result.words.map(\.kind) == ["match", "substituted", "match", "match", "missing", "match"])
        #expect(result.words[1].heard == "chao" && result.words[4].start == result.words[3].end)
        #expect(result.extra.map(\.text) == ["nhé"])
        #expect(abs(result.similarity - 4.0 / 6) < 1e-9)
    }

    @Test("Script lines become cues timed by the speech, with the script's own text")
    func scriptCues() {
        let aligned = TextAlignment.cues(
            script: "Xin chào các bạn!\n\nHôm nay đi chợ.", heard: heard("xin chào các bạn hôm nay đi chợ", start: 1))
        #expect(aligned.cues.map(\.text) == ["Xin chào các bạn!", "Hôm nay đi chợ."])
        #expect(aligned.cues[0].start == 1 && abs(aligned.cues[1].start - 3) < 1e-9)
        #expect(aligned.words.count == 8 && aligned.alignment.similarity == 1)
    }

    @Test("Rate per speaker over phrases: p10/p50/p90, overall and articulation")
    func rate() {
        let words = heard("một hai ba bốn năm sáu", step: 0.25).map { word in
            CaptionWords.Timed(text: word.text, start: word.start, end: word.start + 0.2, speaker: "A")
        }
        let transcript = SourceTranscript(
            key: "k", language: "vi", provider: [:], transcribedAt: "", phrases: [
                SubRip.Cue(start: 0, end: 1, text: "một hai ba bốn"), SubRip.Cue(start: 1, end: 2, text: "năm sáu"),
            ], words: words)
        let json = SpeechRate.json(transcript, unit: .syllables).object
        #expect(json["unit"] == .string("syllables"))
        let speaker = json["speakers"]?.array.first?.object
        #expect(speaker?["speaker"] == .string("A") && speaker?["units"] == .integer(6))
        #expect(speaker?["rate"]?.object["p50"] == .number(4) || speaker?["rate"]?.object["p50"] == .number(2))
        #expect(speaker?["overall"] == .number(3))
        #expect(speaker?["articulation"] == .number(5))
    }

    @Test("Narration windows: speech-free stretches with anchors, covered shares, shots and a budget at the caller's rate")
    func windows() throws {
        var project = Project(name: "VO", fps: FrameRate(30, 1))
        project.media = [Media(fields: ["id": .string("m"), "path": .string("m.mp4"), "fps": FrameRate(30, 1).json, "frames": .integer(900)])]
        let main = project.tracks.firstIndex { $0.role == TrackRole.main }!
        project.tracks[main].items = [
            Item(id: "a", media: "m", at: 0, duration: 150), Item(id: "b", media: "m", at: 150, duration: 150, sourceIn: 300),
        ]
        let music = project.tracks.firstIndex { $0.role == TrackRole.music }!
        project.tracks[music].items = [Item(id: "mu", media: "m", at: 0, duration: 300)]
        let words = [ReviewSync.WordSpan(at: 0, end: 60, text: "xin"), ReviewSync.WordSpan(at: 240, end: 270, text: "chào")]
        let json = NarrationWindows.json(project, words: words, minSeconds: 2, rate: 4, unit: .syllables).object
        let windows = try #require(json["windows"]?.array).map(\.object)
        #expect(windows.count == 1)
        #expect(windows[0]["at"] == .integer(60) && windows[0]["end"] == .integer(240))
        #expect(windows[0]["covered"]?.object["music"] == .number(1))
        #expect(windows[0]["owner"] == nil)
        #expect(windows[0]["anchors"]?.object["firstCut"] == .integer(150))
        #expect(windows[0]["anchors"]?.object["afterWord"]?.object["text"] == .string("xin"))
        #expect(windows[0]["budget"]?.object["units"] == .integer(24))
        #expect(windows[0]["shots"]?.array.count == 2)
    }

    @Test("Grouping: the agent's groups or a full rule; captions under the words are replaced; facts listed")
    func grouping() throws {
        var project = Project(name: "Caps", fps: FrameRate(30, 1))
        let captions = project.tracks.firstIndex { $0.role == TrackRole.captions }!
        var old = Item(id: "old", at: 0, duration: 120)
        old["text"] = .string("một hai ba bốn")
        old["textPreset"] = .string("bold-outline")
        project.tracks[captions].items = [old]
        let words = [
            ReviewSync.WordSpan(at: 0, end: 20, text: "một"), ReviewSync.WordSpan(at: 25, end: 45, text: "hai"),
            ReviewSync.WordSpan(at: 80, end: 100, text: "ba"), ReviewSync.WordSpan(at: 102, end: 120, text: "bốn"),
        ]
        let rule = CaptionGrouping.groups(words, rule: .init(maxChars: 20, maxSeconds: 5, breakGapSeconds: 0.5), fps: 30)
        #expect(rule == [[0, 1], [2, 3]])
        let planned = try CaptionGrouping.operation(project, words: words, groups: [[0, 1, 2], [3]], author: .agent)
        let next = try project.applying(planned.operation).project
        let items = try #require(next.tracks.first { $0.role == TrackRole.captions }).items.sorted { $0.at < $1.at }
        #expect(items.map(\.text) == ["một hai ba", "bốn"] && items[0].textPreset == "bold-outline")
        #expect(items[0]["words"]?.array.count == 3)
        let facts = CaptionGrouping.facts(planned.cues, fps: 30).object
        #expect(facts["gaps"]?.array.first?.object["frames"] == .integer(2))
        #expect(throws: ProjectError.self) { _ = try CaptionGrouping.operation(project, words: words, groups: [[1, 0]], author: .agent) }
    }

    @Test("Numbers spell out the way they are said, in Vietnamese and English")
    func numberWords() {
        #expect(NumberWords.spelled("528", language: "vi") == ["năm", "trăm", "hai", "mươi", "tám"])
        #expect(NumberWords.spelled("15", language: "vi") == ["mười", "năm"])
        #expect(NumberWords.spelled("105", language: "vi") == ["một", "trăm", "lẻ", "năm"])
        #expect(NumberWords.spelled("2.005", language: "vi") == ["hai", "nghìn", "không", "trăm", "lẻ", "năm"])
        #expect(NumberWords.spelled("7,5", language: "vi") == ["bảy", "phẩy", "năm"])
        #expect(NumberWords.spelled("50%", language: "vi") == ["năm", "mươi", "phần", "trăm"])
        #expect(NumberWords.spelled("1,250", language: "en") == ["one", "thousand", "two", "hundred", "fifty"])
        #expect(NumberWords.spelled("hello", language: "vi") == nil)
        #expect(NumberWords.language(of: "Hồ Tây rộng") == "vi" && NumberWords.language(of: "Lake area") == "en")
    }

    @Test("A spelled-out number in the script matches the digits a recognizer wrote, in either common spelling")
    func numbersMatchDigits() {
        let heard = [("Hồ", 0.0, 0.2), ("Tây", 0.2, 0.4), ("rộng", 0.4, 0.6), ("528", 0.6, 1.6), ("hecta.", 1.6, 2.0)].map {
            CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2)
        }
        let result = TextAlignment.align("Hồ Tây rộng năm trăm hai mươi tám héc ta.", to: heard)
        #expect(result.words.filter { $0.kind == "match" }.count == 8)
        let tam = result.words.first { $0.text == "tám" }
        #expect(tam?.kind == "match" && (tam?.start ?? 0) >= 1.4 && (tam?.end ?? 0) <= 1.6, "a fifth of the numeral's time")
        let variant = TextAlignment.align("hai mươi mốt", to: [CaptionWords.Timed(text: "21", start: 0, end: 1)])
        #expect(variant.similarity == 1, "mốt and một are one number")
        let digits = TextAlignment.align("Giá 50 nghìn", to: [("Giá", 0.0, 0.3), ("50", 0.3, 0.6), ("nghìn", 0.6, 0.9)].map {
            CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2)
        })
        #expect(digits.similarity == 1, "digits in the script stay digits")
        let joined = TextAlignment.align("ba phẩy năm km", to: [CaptionWords.Timed(text: "3,5km", start: 0, end: 1)])
        #expect(joined.similarity == 1, "a unit written onto the number")
    }
}
