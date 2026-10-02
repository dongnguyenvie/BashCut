import AVFoundation
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct WaveformTests {
    @Test("Stereo peaks retain opposite-phase channels and detect silent regions")
    func audio() async throws {
        let directory = try TestFixtures.temporaryDirectory("waveform")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.wav")
        try makeAudio(url)
        let waveform = try await WaveformAnalyzer().waveform(url: url)
        #expect(waveform.hasAudio)
        #expect(abs(waveform.duration - 1) < 0.01)
        #expect(waveform.peaks.count <= 20000)
        #expect(waveform.peak(from: 0.1, to: 0.3) > 0.7)
        #expect(waveform.peak(from: 0.7, to: 0.9) < 0.001)
        #expect(waveform.peak(from: -2, to: -1) == 0)
        #expect(waveform.peak(from: 1, to: 2) == 0)
    }

    @Test("Disk caches round-trip, reject corrupt data and invalidate on source changes")
    func cache() async throws {
        let directory = try TestFixtures.temporaryDirectory("waveform")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.wav")
        let cache = directory.appendingPathComponent("cache")
        try makeAudio(url)
        let analyzer = WaveformAnalyzer()
        let first = try await analyzer.waveform(url: url, cacheDirectory: cache)
        let second = try await WaveformAnalyzer().waveform(url: url, cacheDirectory: cache)
        #expect(first == second)
        let cached = try #require(
            FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: cached)
        #expect(try await WaveformAnalyzer().waveform(url: url, cacheDirectory: cache) == first)
        try makeAudio(url, amplitude: 0.2)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        let changed = try await analyzer.waveform(url: url, cacheDirectory: cache)
        #expect(changed.peak(from: 0.1, to: 0.3) < 0.3)
        #expect(changed != first)
    }

    @Test("Peak queries clamp to time bounds and reject invalid intervals")
    func peakRanges() {
        let waveform = AudioWaveform(duration: 4, peaks: [0.1, 0.8, 0.3, 0.2])
        #expect(waveform.peak(from: 1.1, to: 1.8) == 0.8)
        #expect(waveform.peak(from: 2.1, to: 2.9) == 0.3)
        #expect(waveform.peak(from: 3.1, to: 100) == 0.2)
        #expect(waveform.peak(from: .nan, to: 1) == 0)
        #expect(waveform.peak(from: 2, to: 1) == 0)
    }

    /// One second of 8 kHz stereo: a 400 Hz tone with opposite-phase channels, silent after 0.5 s.
    private func makeAudio(_ url: URL, amplitude: Float = 0.8) throws {
        try TestFixtures.writeTone(
            to: url, seconds: 1, sampleRate: 8000, channels: 2,
            tone: TestFixtures.Tone(frequency: 400, amplitude: amplitude, silentAfter: 0.5))
    }
}
