import Foundation
import Testing

@testable import BashCutProject

/// Speech spans with the calibration used (P0-A3): `media.speech-map`.
struct SpeechMapTests {
    /// 0.1 s windows over `seconds`: `loud` dB inside the spans, `floor` elsewhere, each with ±`jitter` dB of
    /// repeatable noise.
    func sound(seconds: Double, loud spans: [(Double, Double)], loud: Double, floor: Double, jitter: Double = 1)
        -> MediaAnalysis.Sound
    {
        let levels = (0..<Int(seconds * 10)).map { index -> Double in
            let time = (Double(index) + 0.5) / 10
            let base = spans.contains { time >= $0.0 && time < $0.1 } ? loud : floor
            return base + jitter * sin(Double(index) * 2.399)
        }
        return MediaAnalysis.Sound(window: 0.1, levels: levels, peakDb: loud + 3)
    }

    func spans(_ value: JSONValue?) -> [[Double]] {
        (value?.array ?? []).map { [$0.object["start"]?.double ?? -1, $0.object["end"]?.double ?? -1] }
    }

    @Test("Speech well over the floor separates clearly; spans, gaps and the calibration are reported")
    func clear() throws {
        let json = SpeechMap.json(
            sound: sound(seconds: 6, loud: [(1, 2), (4, 5)], loud: -20, floor: -60), words: nil).object
        let calibration = try #require(json["calibration"]).object
        #expect(calibration["separation"] == .string("clear"))
        #expect(calibration["method"] == .string("otsu"))
        let separation = try #require(calibration["separationDb"]?.double)
        #expect(abs(separation - 40) < 2)
        #expect(spans(json["spans"]) == [[1, 2], [4, 5]])
        #expect(spans(json["gaps"]) == [[0, 1], [2, 4], [5, 6]])
        #expect(json["speechSeconds"] == .number(2))
        #expect(json["gapStats"]?.object["maxSeconds"] == .number(2))
        #expect(json["transcript"] == .null)
    }

    @Test("A noisy street does not separate: no made-up silences, unless a threshold is given")
    func noisy() throws {
        let street = sound(seconds: 6, loud: [(1, 2), (4, 5)], loud: -27, floor: -30, jitter: 2)
        let json = SpeechMap.json(sound: street, words: nil).object
        #expect(json["calibration"]?.object["separation"] == .string("none"))
        #expect(json["calibration"]?.object["thresholdDb"] == .null)
        #expect(json["spans"] == .null)
        #expect(json["reason"]?.string?.contains("do not separate") == true)

        let forced = SpeechMap.json(sound: street, words: nil, parameters: .init(thresholdDb: -100)).object
        #expect(forced["calibration"]?.object["separation"] == .string("given"))
        #expect(spans(forced["spans"]) == [[0, 6]])
    }

    @Test("Digital silence is quiet but not part of the calibration")
    func digitalSilence() throws {
        var levels = [Double](repeating: MediaAnalysis.silenceDb, count: 20)
        levels += (0..<40).map { -30 + sin(Double($0) * 2.399) }
        let json = SpeechMap.json(sound: .init(window: 0.1, levels: levels, peakDb: -25), words: nil).object
        #expect(json["calibration"]?.object["separation"] == .string("none"))
        #expect(json["digitalSilenceSeconds"] == .number(2))
        #expect(SpeechMap.calibrate([MediaAnalysis.silenceDb, -30]) == nil)
    }

    @Test("Transcript spans and how far they agree with the level spans")
    func transcript() throws {
        let words: [CaptionWords.Timed] = [
            .init(text: "a", start: 1.0, end: 1.4), .init(text: "b", start: 1.5, end: 2.0),
            .init(text: "c", start: 4.0, end: 4.5),
        ]
        let json = SpeechMap.json(
            sound: sound(seconds: 6, loud: [(1, 2), (4, 5)], loud: -20, floor: -60), words: words).object
        let transcript = try #require(json["transcript"]).object
        #expect(spans(transcript["spans"]) == [[1, 2], [4, 4.5]])
        #expect(transcript["words"] == .integer(3))
        #expect(transcript["levelCoveredByWords"] == .number(0.75))
        #expect(transcript["wordsCoveredByLevel"] == .number(1))
    }
}
