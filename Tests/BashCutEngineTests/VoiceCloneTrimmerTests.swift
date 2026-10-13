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

    @Test("A source file is trimmed to a 24 kHz mono WAV of the chosen window")
    func trimsFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.wav")
        try VoiceCloneAudio.write(Self.silence(2) + Self.speech(10) + Self.silence(2), to: source)
        let output = folder.appendingPathComponent("reference.wav")
        let trim = try await VoiceCloneAudio.trim(
            source: source, range: 1...14, minSeconds: 3, maxSeconds: 8, output: output)
        #expect(trim.start >= 1 && trim.end <= 14 && trim.seconds <= 8.01 && trim.seconds >= 3)
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.sampleRate == 24_000 && file.fileFormat.channelCount == 1)
        #expect(abs(Double(file.length) / 24_000 - trim.seconds) < 0.06)
    }
}
