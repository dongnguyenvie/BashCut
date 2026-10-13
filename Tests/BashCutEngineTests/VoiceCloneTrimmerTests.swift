import AVFoundation
@testable import BashCutEngine
import Foundation
import Testing

/// Choosing a clone reference window from generated sound (#532): no real media, no ML.
struct VoiceCloneTrimmerTests {
    static let rate = 24_000.0

    /// Low noise (deterministic) for `seconds`.
    static func silence(_ seconds: Double, level: Float = 0.002) -> [Float] {
        var seed: UInt32 = 7
        return (0..<Int(seconds * rate)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 2 * level
        }
    }

    /// Syllable-like bursts: 0.25 s of a 220 Hz tone, 0.1 s pause, for `seconds`.
    static func speech(_ seconds: Double, amplitude: Float = 0.3, clipped: Bool = false) -> [Float] {
        (0..<Int(seconds * rate)).map { index in
            let time = Double(index) / rate
            guard time.truncatingRemainder(dividingBy: 0.35) < 0.25 else { return 0.001 }
            let value = amplitude * Float(sin(2 * .pi * 220 * time))
            return clipped ? (value >= 0 ? 1 : -1) : value
        }
    }

    @Test("The window is the speech between silences, within the provider's range, with passing checks")
    func choosesSpeech() throws {
        let samples = Self.silence(3) + Self.speech(7) + Self.silence(5)
        let window = try VoiceCloneTrimmer.choose(samples, rate: Self.rate, minSeconds: 3, maxSeconds: 8)
        #expect(window.seconds >= 3 && window.seconds <= 8)
        #expect(window.start >= 2.8 && window.end <= 10.3)
        let failed = window.checks.filter { !$0.passed }.map(\.id)
        #expect(failed.isEmpty, "failed checks: \(failed)")
        #expect(Set(window.checks.map(\.id)) == ["length", "loudness", "speech", "gaps", "noise", "clipping"])
    }

    @Test("Too short, too quiet, mostly silence and clipped sources are refused with the reason")
    func refusals() {
        let cases: [([Float], String)] = [
            (Self.speech(2), "tooShort"),
            (Self.silence(2) + Self.speech(6, amplitude: 0.002), "tooQuiet"),
            (Self.silence(20) + Self.speech(3), "mostlySilence"),
            (Self.silence(1) + Self.speech(8, clipped: true), "clipped"),
        ]
        for (samples, reason) in cases {
            do {
                _ = try VoiceCloneTrimmer.choose(samples, rate: Self.rate, minSeconds: 3, maxSeconds: 8)
                Issue.record("expected \(reason)")
            } catch let refusal as VoiceCloneRefusal {
                #expect(refusal.reason == reason)
                #expect(!refusal.checks.isEmpty)
            } catch {
                Issue.record("unexpected \(error)")
            }
        }
    }

    /// Classifier output: `speech` and `music` confidence for frames in the given seconds.
    static func classes(seconds: Double, speech: ClosedRange<Double>, music: Double = 0) -> VoiceCloneClassification {
        let count = Int(seconds / VoiceCloneTrimmer.frame)
        let speechValues = (0..<count).map { speech.contains(Double($0) * VoiceCloneTrimmer.frame) ? 0.9 : 0.05 }
        return VoiceCloneClassification(speech: speechValues, music: Array(repeating: music, count: count))
    }

    @Test("With the classifier's mask, talk over steady traffic noise is speech (the level threshold alone misses it)")
    func maskOverNoise() throws {
        // 20 s of loud noise with a tone on top all the way: levels see almost no contrast.
        let samples = zip(Self.silence(20, level: 0.2), Self.speech(20)).map { $0 + $1 * 0.3 }
        let classes = Self.classes(seconds: 20, speech: 5...15)
        let window = try VoiceCloneTrimmer.choose(samples, rate: Self.rate, minSeconds: 3, maxSeconds: 8, classes: classes)
        #expect(window.start >= 4.8 && window.end <= 15.3 && window.seconds >= 3)
        let ids = window.checks.map(\.id)
        #expect(ids.contains("music") && window.checks.first { $0.id == "speech" }?.passed == true)
    }

    @Test("Music under the voice refuses with musicUnder")
    func musicUnder() {
        let classes = Self.classes(seconds: 12, speech: 0...12, music: 0.9)
        do {
            _ = try VoiceCloneTrimmer.choose(Self.speech(12), rate: Self.rate, minSeconds: 3, maxSeconds: 8, classes: classes)
            Issue.record("expected musicUnder")
        } catch let refusal as VoiceCloneRefusal {
            #expect(refusal.reason == "musicUnder")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("The sound classifier runs on generated sound and gives one value per frame")
    func classifierRuns() throws {
        let classes = try #require(try VoiceCloneClassifier.classify(Self.silence(1) + Self.speech(4), rate: Self.rate))
        #expect(classes.speech.count == 100 && classes.music.count == 100)
        #expect(classes.speech.allSatisfy { (0...1).contains($0) })
    }

    @Test("A source file is trimmed to a 24 kHz mono WAV of the chosen window")
    func trimsFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try VoiceCloneAudio.write(Self.silence(2) + Self.speech(10) + Self.silence(2), to: source)
        let output = folder.appendingPathComponent("reference.wav")
        let trim = try await VoiceCloneAudio.trim(
            source: source, range: 1...14, minSeconds: 3, maxSeconds: 8, output: output, classify: false)
        #expect(trim.start >= 1 && trim.end <= 14 && trim.seconds <= 8.01 && trim.seconds >= 3)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 24_000 && file.fileFormat.channelCount == 1)
        #expect(abs(Double(file.length) / 24_000 - trim.seconds) < 0.06)
    }
}
