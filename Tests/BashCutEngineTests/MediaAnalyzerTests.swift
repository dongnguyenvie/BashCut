@preconcurrency import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// The measured record of a source file (P0-A1) on generated media: an exact-frame cut, file facts, sound levels and
/// the content-keyed cache.
struct MediaAnalyzerTests {
    @Test("A hard cut is found on its exact frame; file facts and a still shot's numbers")
    func picture() async throws {
        let root = try TestFixtures.temporaryDirectory("media-analyzer")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cut.mov")
        // Grey 40 for 50 frames, then 200: one hard cut at frame 50, between two samples (every 8 frames at 4/s).
        try await PictureSamplerTests.writeMovie(to: url, frames: 120) { $0 < 50 ? 40 : 200 }
        let key = try MediaAnalyzer.key(for: url)
        let record = try await MediaAnalyzer.measure(url, key: key, fps: FrameRate(30, 1), frames: 120)
        let picture = try #require(record.picture)
        #expect(picture.interval == 8)
        #expect(picture.samples.count == 15)
        #expect(picture.candidates.map(\.frame) == [50], "\(picture.candidates)")
        #expect((picture.candidates.first?.score ?? 0) > 0.4)
        #expect(picture.samples.allSatisfy { $0.colourfulness < 0.02 }, "grey picture")
        #expect(picture.samples.allSatisfy { $0.sharpness >= 0 && $0.sharpness < 0.05 }, "smooth ramp")
        let video = try #require(record.tech.video)
        #expect(video.width == 160 && video.height == 90)
        #expect(video.codec == "avc1")
        #expect(video.frames == 120)
        #expect(abs((video.minFrameSeconds ?? 0) - 1 / 30.0) < 1e-4 && abs((video.maxFrameSeconds ?? 0) - 1 / 30.0) < 1e-4)
        #expect(record.tech.audio == nil && record.sound == nil)
        let shots = try #require(record.json().object["picture"]?.object["shots"]?.array)
        #expect(shots.map { $0.object["duration"] } == [.integer(50), .integer(70)])

        // Kept by content: a copy under another name has the same key, a changed file another one.
        try MediaAnalyzer.save(record, projectRoot: root)
        let copy = root.appendingPathComponent("renamed.mov")
        try FileManager.default.copyItem(at: url, to: copy)
        #expect(try MediaAnalyzer.key(for: copy) == key)
        #expect(MediaAnalyzer.load(key: key, projectRoot: root) == record)
        try FileManager.default.removeItem(at: copy)
        try await PictureSamplerTests.writeMovie(to: copy, frames: 60) { _ in 90 }
        #expect(try MediaAnalyzer.key(for: copy) != key)
    }

    @Test("Sound levels: silence, a tone and silence give one active span and the tone's level")
    func sound() async throws {
        let root = try TestFixtures.temporaryDirectory("media-analyzer-sound")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tone.caf")
        let rate = 48_000.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 3)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for index in 0..<Int(rate * 3) {
                let tone = index >= Int(rate) && index < Int(rate * 2)
                samples[index] = tone ? 0.1 * Float(sin(2 * .pi * 997 * Double(index) / rate)) : 0
            }
        }
        try file.write(from: buffer)
        let record = try await MediaAnalyzer.measure(
            url, key: try MediaAnalyzer.key(for: url), fps: FrameRate(30, 1), frames: 0)
        #expect(record.picture == nil)
        #expect(record.tech.audio?.channels == 2)
        let sound = try #require(record.sound)
        #expect(sound.levels.count == 30)
        #expect(abs(sound.peakDb - -20) < 0.5)
        #expect(abs((sound.stereoCorrelation ?? 0) - 1) < 0.01)
        let tone = sound.levels[12..<18]
        #expect(tone.allSatisfy { abs($0 - -23) < 0.5 }, "\(tone)")
        let json = try #require(record.json().object["sound"]?.object)
        let active = try #require(json["active"]?.array).map(\.object)
        #expect(active.count == 1)
        #expect(active.first?["start"] == .number(1))
        #expect(active.first?["end"] == .number(2))
    }
}
