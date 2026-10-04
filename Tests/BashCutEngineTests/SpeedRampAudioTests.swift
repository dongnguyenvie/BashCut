import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct SpeedRampAudioTests {
    @Test("Ramped PCM remains continuous and audible at rate boundaries", arguments: SpeedCurve.presets.map(\.id), [true, false])
    func boundaries(preset: String, preservesPitch: Bool) async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-audio")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.caf"), seconds: 20, tone: .init(frequency: 220, amplitude: 0.2))
        let media = Media(fields: [
            "id": .string("m"), "kind": .string("audio"), "path": .string("tone.caf"),
            "fps": FrameRate().json, "frames": .integer(599)
        ])
        var item = Item(id: "tone", media: "m", at: 0, duration: 180)
        item["preservePitch"] = .bool(preservesPitch)
        let curve = try #require(SpeedCurve.preset(preset))
        let project = try Project(name: "Ramp tone").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: item), .setSpeedCurve(item: "tone", curve: curve, keepDuration: true)
        ])).project
        let built = try await CompositionBuilder().build(project, root: root)
        let track = try #require(built.composition.tracks(withMediaType: .audio).first)
        let samples = try decode(built)
        #expect(track.segments.filter { !$0.isEmpty }.count == 1)
        #expect(samples.allSatisfy { $0.isFinite })
        #expect(abs(Double(samples.count) / 48_000 - project.fps.time(180).seconds) < 2 / 48_000.0)
        var maximumJump: Float = 0, minimumRMS = Double.infinity
        for piece in SpeedRampPlan(curve: curve, item: item, mediaFPS: media.fps, fps: project.fps).pieces.dropFirst() {
            let center = Int((piece.target.start.seconds * 48_000).rounded())
            let lower = max(1, center - 480), upper = min(samples.count, center + 480)
            guard upper > lower else { continue }
            var energy = 0.0
            for index in lower..<upper {
                maximumJump = max(maximumJump, abs(samples[index] - samples[index - 1]))
                energy += Double(samples[index] * samples[index])
            }
            minimumRMS = min(minimumRMS, sqrt(energy / Double(upper - lower)))
        }
        print("RAMP_PCM preset=\(preset) pitch=\(preservesPitch) pieces=\(track.segments.count) jump=\(maximumJump) min_rms=\(minimumRMS)")
        // A 0.2-amplitude tone at the fastest 5x preset has at most a 0.029 sample-to-sample slope.
        // Allow resampling/phase-vocoder transients, but reject clicks and 20ms boundary dropouts.
        #expect(maximumJump < 0.08)
        #expect(minimumRMS > 0.04)
        for window in [Array(samples.prefix(960)), Array(samples.suffix(960))] {
            #expect(sqrt(window.reduce(0.0) { $0 + Double($1 * $1) } / Double(window.count)) > 0.04)
        }
        let center = Int(project.fps.time(90).seconds * 48_000)
        let window = samples[(center - 4_800)..<(center + 4_800)]
        let crossings = zip(window, window.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        let frequency = Double(crossings) / 0.2
        let seconds = project.fps.time(180).seconds
        let averageRate = curve.integral(from: 0.5 - 0.1 / seconds, to: 0.5 + 0.1 / seconds) * seconds / 0.2
        let expectedFrequency = preservesPitch ? 220 : 220 * averageRate
        #expect(abs(frequency - expectedFrequency) < max(10, expectedFrequency * 0.06))
    }

    @Test("A source sound ending stays aligned after trimming and ramping", arguments: [true, false], [4.0, 6.0, 9.0])
    func sourceTiming(preservesPitch: Bool, silence: Double) async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-marker")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.caf"), seconds: 20,
                                   tone: .init(frequency: 220, amplitude: 0.2, silentAfter: silence))
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.caf"),
                                   "fps": FrameRate().json, "frames": .integer(599)])
        var item = Item(id: "tone", media: "m", at: 0, duration: 180, sourceIn: 30)
        item["preservePitch"] = .bool(preservesPitch)
        let curve = try #require(SpeedCurve.preset("hero"))
        let project = try Project(name: "Marker").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: item), .setSpeedCurve(item: "tone", curve: curve, keepDuration: true)
        ])).project
        let renderedItem = try #require(project.tracks.flatMap(\.items).first)
        let expected = renderedItem.timelineFrames(atSourceSeconds: silence - media.fps.time(30).seconds, fps: project.fps) / project.fps.value
        let samples = try decode(try await CompositionBuilder().build(project, root: root))
        var lastSound = 0.0
        for start in stride(from: 0, to: samples.count - 480, by: 480) {
            let window = samples[start..<(start + 480)]
            let rms = sqrt(window.reduce(0.0) { $0 + Double($1 * $1) } / 480)
            if rms > 0.04 { lastSound = Double(start + 240) / 48_000 }
        }
        print("RAMP_ALIGNMENT pitch=\(preservesPitch) expected=\(expected) observed=\(lastSound)")
        #expect(abs(lastSound - expected) < 0.025)
    }

    @Test("Pitch preservation covers low fundamentals and higher tones", arguments: [60.0, 100.0, 440.0, 2_000.0])
    func pitchRange(frequency: Double) async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-pitch")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.caf"), seconds: 20,
                                   tone: .init(frequency: frequency, amplitude: 0.2))
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.caf"),
                                   "fps": FrameRate().json, "frames": .integer(599)])
        let project = try Project(name: "Pitch").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: Item(id: "a", media: "m", at: 0, duration: 180)),
            .setSpeedCurve(item: "a", curve: try #require(SpeedCurve.preset("hero")), keepDuration: true)
        ])).project
        let samples = try decode(try await CompositionBuilder().build(project, root: root))
        for start in [48_000, 120_000, 216_000] {
            let window = samples[start..<(start + 24_000)]
            let crossings = zip(window, window.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
            #expect(abs(Double(crossings) * 2 - frequency) < max(4, frequency * 0.04))
            #expect(sqrt(window.reduce(0.0) { $0 + Double($1 * $1) } / Double(window.count)) > 0.08)
        }
    }

    @Test("Supported speed extremes retain duration and usable PCM", arguments: [0.1, 16.0], [true, false])
    func speedExtremes(speed: Double, preservesPitch: Bool) async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-extreme")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.caf"), seconds: 20,
                                   tone: .init(frequency: 100, amplitude: 0.2))
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.caf"),
                                   "fps": FrameRate().json, "frames": .integer(599)])
        var item = Item(id: "a", media: "m", at: 0, duration: 30)
        item["preservePitch"] = .bool(preservesPitch)
        let curve = try SpeedCurve([.init(t: 0, speed: speed), .init(t: 1, speed: speed)])
        let project = try Project(name: "Extreme").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: item), .setSpeedCurve(item: "a", curve: curve, keepDuration: true)
        ])).project
        let samples = try decode(try await CompositionBuilder().build(project, root: root))
        #expect(abs(Double(samples.count) / 48_000 - project.fps.time(30).seconds) < 2 / 48_000.0)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) < 0.3 })
        let window = samples[9_600..<38_400]
        let crossings = zip(window, window.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        let expected = preservesPitch ? 100 : 100 * speed
        #expect(abs(Double(crossings) / 0.6 - expected) < max(4, expected * 0.02))
        #expect(sqrt(window.reduce(0.0) { $0 + Double($1 * $1) } / Double(window.count)) > 0.08)
    }

    private func decode(_ snapshot: CompositionSnapshot) throws -> [Float] {
        let reader = try AVAssetReader(asset: snapshot.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: snapshot.composition.tracks(withMediaType: .audio), audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        output.audioMix = snapshot.audioMix
        reader.add(output)
        #expect(reader.startReading())
        var result: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(buffer))
            var samples = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes {
                guard let address = $0.baseAddress else { return OSStatus(-1) }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: address)
            }
            #expect(status == kCMBlockBufferNoErr)
            result.append(contentsOf: samples)
        }
        #expect(reader.status == .completed)
        return result
    }
}
