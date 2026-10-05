import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct SpeedRampAudioCacheTests {
    private func project(root: URL) throws -> Project {
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.caf"), seconds: 6, channels: 2)
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.caf"),
                                   "fps": FrameRate().json, "frames": .integer(179)])
        return try Project(name: "Cache").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: Item(id: "a", media: "m", at: 0, duration: 30)),
            .setSpeedCurve(item: "a", curve: SpeedCurve.preset("hero"), keepDuration: true)
        ])).project
    }

    @Test("Rendered ramp cache survives gain edits, keeps stereo, and invalidates on curve/pitch/source changes")
    func invalidation() async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-cache")
        defer { try? FileManager.default.removeItem(at: root) }
        var value = try project(root: root)
        let builder = CompositionBuilder()
        let first = try await builder.build(value, root: root)
        let url = try #require(first.composition.tracks(withMediaType: .audio).first?.segments.first?.sourceURL)
        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.channelCount == 2)
        let samples = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800))
        try file.read(into: samples)
        let channels = try #require(samples.floatChannelData)
        #expect((0..<Int(samples.frameLength)).allSatisfy { abs(channels[0][$0] + channels[1][$0]) < 0.001 })
        value = try value.applying(.setProperties(item: "a", patch: ["volumeDb": .number(-6)])).project
        _ = try await builder.build(value, root: root)
        #expect(await builder.rampAudioRenders == 1)
        value = try value.applying(.setSpeedCurve(item: "a", curve: SpeedCurve.preset("bullet"), keepDuration: true)).project
        _ = try await builder.build(value, root: root)
        #expect(await builder.rampAudioRenders == 2)
        value = try value.applying(.setProperties(item: "a", patch: ["preservePitch": .bool(false)])).project
        _ = try await builder.build(value, root: root)
        #expect(await builder.rampAudioRenders == 3)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)],
                                              ofItemAtPath: root.appendingPathComponent("tone.caf").path)
        let changed = try await builder.build(value, root: root)
        #expect(await builder.rampAudioRenders == 4)
        let changedURL = try #require(changed.composition.tracks(withMediaType: .audio).first?.segments.first?.sourceURL)
        try Data().write(to: changedURL)
        _ = try await builder.build(value, root: root)
        #expect(await builder.rampAudioRenders == 5)
    }
    @Test("Cancelling a live ramp render removes staging files and never publishes partial audio")
    func cancellation() async throws {
        let root = try TestFixtures.temporaryDirectory("ramp-cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try project(root: root)
        let value = try base.applying(.setSpeedCurve(item: "a",
            curve: SpeedCurve([.init(t: 0, speed: 0.1), .init(t: 1, speed: 0.1)]), keepDuration: false)).project
        let builder = CompositionBuilder()
        let task = Task { try await builder.build(value, root: root) }
        let directory = ProjectCache.url(.rampAudio, projectRoot: root)
        var began = false
        for _ in 0..<500 {
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            if entries.contains(where: { $0.pathExtension.isEmpty }) { began = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(began)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(await builder.rampAudioRenders == 0)
    }

}
