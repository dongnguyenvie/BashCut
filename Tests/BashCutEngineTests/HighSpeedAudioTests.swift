import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

/// AVFoundation's offline audio mixer deadlocks inside `copyNextSampleBuffer` on compressed sound scaled past about 8×,
/// which hung every export and mix measurement of a 16× time-lapse; cancelling that job then crashed the app.
struct HighSpeedAudioTests {
    private static let speed = 16.0

    @Test("Sound sped up 16× renders offline and its mix exports")
    func sixteenTimes() async throws {
        let root = try TestFixtures.temporaryDirectory("high-speed-audio")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.m4a"), seconds: 20, channels: 2, aac: true)
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.m4a"),
                                   "fps": FrameRate().json, "frames": .integer(600)])
        let project = try Project(name: "Time-lapse").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: Item(id: "a", media: "m", at: 0, duration: 432)),
            .setSpeed(item: "a", speed: Self.speed, keepDuration: false),
        ])).project
        #expect(project.tracks.flatMap(\.items).first?.duration == 27)
        let engine = AVFoundationRenderEngine(source: OriginalMediaSource())
        let snapshot = try await engine.build(project, root: root, purpose: .export)
        let source = try #require(snapshot.composition.tracks(withMediaType: .audio).first?.segments.first?.sourceURL)
        #expect(source.deletingLastPathComponent().standardizedFileURL
            == ProjectCache.url(.rampAudio, projectRoot: root).standardizedFileURL)
        let file = root.appendingPathComponent("mix.caf")
        try await Self.within(.seconds(30)) { _ = try await Exporter().exportAudio(snapshot, to: file) }
        let length = try AVAudioFile(forReading: file).length
        #expect(abs(Double(length) / 48_000 - 0.9) < 0.05)
    }

    /// Twelve 2–4× clips the composition scaled itself froze the audio mix output near 144 s of a 180 s export, and
    /// dropping the ones there moved the freeze to the next scaled clip.
    @Test("An export renders 2–4× sound offline; preview still scales it", arguments: [2.0, 3.0, 4.0])
    func moderateSpeedExport(speed: Double) async throws {
        let root = try TestFixtures.temporaryDirectory("moderate-speed-audio")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.m4a"), seconds: 20, channels: 2, aac: true)
        let media = Media(fields: ["id": .string("m"), "kind": .string("audio"), "path": .string("tone.m4a"),
                                   "fps": FrameRate().json, "frames": .integer(600)])
        let project = try Project(name: "Sped up").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "a3", item: Item(id: "a", media: "m", at: 0, duration: 240)),
            .setSpeed(item: "a", speed: speed, keepDuration: false),
        ])).project
        let engine = AVFoundationRenderEngine(source: OriginalMediaSource())
        let ramps = ProjectCache.url(.rampAudio, projectRoot: root).standardizedFileURL
        let export = try await engine.build(project, root: root, purpose: .export)
        let exported = try #require(export.composition.tracks(withMediaType: .audio).first?.segments.first?.sourceURL)
        #expect(exported.deletingLastPathComponent().standardizedFileURL == ramps)
        let preview = try await engine.build(project, root: root, purpose: .preview)
        let previewed = try #require(preview.composition.tracks(withMediaType: .audio).first?.segments.first?.sourceURL)
        #expect(previewed.deletingLastPathComponent().standardizedFileURL != ramps)
        let file = root.appendingPathComponent("mix.caf")
        try await Self.within(.seconds(30)) { _ = try await Exporter().exportAudio(export, to: file) }
        let length = try AVAudioFile(forReading: file).length
        #expect(abs(Double(length) / 48_000 - 8 / speed) < 0.05)
    }

    @Test("Cancelling a render stuck in AVFoundation's mixer ends the job without crashing")
    func cancelStuckRender() async throws {
        let root = try TestFixtures.temporaryDirectory("stuck-mixer")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("tone.m4a")
        try TestFixtures.writeTone(to: url, seconds: 20, channels: 2, aac: true)
        // The composition scales the sound itself, as builds before the fix did.
        let composition = AVMutableComposition()
        let audio = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let asset = AVURLAsset(url: url) // Held: a track of a released asset cannot be inserted.
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let span = CMTimeRange(start: CMTime(value: 1, timescale: 1), duration: CMTime(value: 144, timescale: 10))
        try audio.insertTimeRange(span, of: track, at: .zero)
        audio.scaleTimeRange(CMTimeRange(start: .zero, duration: span.duration),
                             toDuration: CMTime(value: 9, timescale: 10))
        let snapshot = CompositionSnapshot(
            composition: composition, videoComposition: AVMutableVideoComposition(), audioMix: AVMutableAudioMix(),
            structure: nil, undecodable: [], renderFailures: RenderFailures())
        let task = Task { try await Exporter().exportAudio(snapshot, to: root.appendingPathComponent("stuck.caf")) }
        try await Task.sleep(for: .seconds(1))
        task.cancel()
        // A future macOS may no longer deadlock and finish first; either way the call must return promptly.
        try await Self.within(.seconds(10)) { _ = try? await task.value }
    }

    private static func within(_ limit: Duration, _ body: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { try await body(); return true }
            group.addTask { try await Task.sleep(for: limit); return false }
            let finished = try await group.next() ?? false
            group.cancelAll()
            try #require(finished, "Did not return within \(limit)")
        }
    }
}
