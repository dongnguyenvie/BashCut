import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct LongExportTests {
    @Test("Five-minute synthetic export benchmark with encoded frame and audio verification",
           .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_LONG_EXPORT_BENCH"] == "1"))
    func benchmark() async throws {
        _ = try TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("long-export")
        defer { try? FileManager.default.removeItem(at: root) }
        let media = Media(fields: ["id": .string("m"), "path": .string("test.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        let count = 200, clipFrames = 45
        let ops: [EditOperation] = [.setFormat(width: 160, height: 90), .addMedia(media)] + (0..<count).map {
            .insert(track: "v1", item: Item(id: "c-\($0)", media: "m", at: $0 * clipFrames, duration: clipFrames))
        }
        let project = try Project(name: "Long export").applying(.group(label: "Fixture", author: .user, ops: ops)).project
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        let url = root.appendingPathComponent("movie.mp4")
        let start = ContinuousClock.now
        let receipt = try await Exporter().export(snapshot, to: url, settings: ExportSettings(preset: .quickDraft))
        let elapsed = start.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let buffer = output.copyNextSampleBuffer() { frames += CMSampleBufferGetNumSamples(buffer) }
        #expect(reader.status == .completed)
        #expect(frames == count * clipFrames)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - project.fps.time(project.duration).seconds) < 0.05)
        let report: [String: Any] = [
            "scenario": "five-minute-av-export", "sha": ProcessInfo.processInfo.environment["BASHCUT_BENCH_SHA"] ?? "unknown",
            "timelineSeconds": receipt.duration, "exportSeconds": seconds, "fps": Double(frames) / seconds,
            "frames": frames, "width": 160, "height": 90, "bytes": receipt.bytes,
            "os": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("LONG_EXPORT " + (try #require(String(data: json, encoding: .utf8))))
    }
}
