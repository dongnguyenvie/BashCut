import AVFoundation
import AppKit
import BashCutProject
import BashCutTestSupport
import CoreImage
import SnapshotTesting
import Testing

@testable import BashCutEngine

struct EngineTests {
    @Test("Generated footage renders through the shared compositor with captions and audio")
    func render() async throws {
        _ = try TestFixtures.requireVideo()
        let mediaRoot = TestFixtures.mediaRoot
        let performance = ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"
        let count = performance ? 20 : 2
        var project = Project(name: "Synthetic engine fixture")
        let asset = Media(fields: [
            "id": .string("source"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var operations: [EditOperation] = [.addMedia(asset)]
        for index in 0..<count {
            var item = Item(id: "clip-\(index)", media: "source", at: index * 45, duration: 45)
            item["transform"] = .object(["zoom": .number(index.isMultiple(of: 2) ? 1 : 1.25)])
            operations.append(.insert(track: "v1", item: item))
        }
        var caption = Item(id: "caption", at: 0, duration: count * 45)
        caption["text"] = .string("Ăn ngon ở Buôn Ma Thuột\nă â đ ê ô ơ ư ỹ")
        operations.append(.insert(track: "t1", item: caption))
        project = try project.applying(.group(label: "Fixture", author: .user, ops: operations)).project
        let snapshot = try await CompositionBuilder().build(project, root: mediaRoot)
        #expect(snapshot.videoComposition.customVideoCompositorClass == BashCutCompositor.self)
        try await verifyPlayer(snapshot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("export.mp4")
        let start = ContinuousClock.now
        try await Exporter().export(snapshot, to: output)
        let elapsed = start.duration(to: .now)
        let rendered = AVURLAsset(url: output)
        let duration = try await rendered.load(.duration)
        #expect(abs(duration.seconds - Double(project.duration) / project.fps.value) < 0.1)
        #expect(try await rendered.loadTracks(withMediaType: .audio).count == 1)
        let tracks = try await rendered.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        let generator = AVAssetImageGenerator(asset: rendered)
        let image = try await generator.image(at: project.fps.time(20)).image
        #expect(image.width == 1080 && image.height == 1920)
        assertSnapshot(
            of: NSImage(cgImage: image, size: CGSize(width: 1080, height: 1920)),
            as: .image(precision: 0.98), named: "vietnamese-caption",
            record: ProcessInfo.processInfo.environment["BASHCUT_RECORD_SNAPSHOTS"] == "1" ? .all : .never
        )
        let fixturePreview = TestFixtures.repositoryRoot.appendingPathComponent("build/engine-preview.png")
        try FileManager.default.createDirectory(
            at: fixturePreview.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = CIContext()
        try context.writePNGRepresentation(
            of: CIImage(cgImage: image), to: fixturePreview,
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        if performance {
            #expect(
                elapsed < .seconds(duration.seconds),
                "Synthetic export must be faster than real time: \(elapsed)")
        } else {
            var draft = project
            var format = draft["format"]?.object ?? [:]
            format["width"] = .integer(720)
            format["height"] = .integer(1280)
            draft["format"] = .object(format)
            let draftSnapshot = try await CompositionBuilder().build(draft, root: mediaRoot)
            let draftOutput = directory.appendingPathComponent("draft.mp4")
            let receipt = try await Exporter().export(
                draftSnapshot, to: draftOutput, settings: ExportSettings(preset: .quickDraft))
            let draftAsset = AVURLAsset(url: draftOutput)
            let draftTrack = try #require(try await draftAsset.loadTracks(withMediaType: .video).first)
            #expect(try await draftTrack.load(.naturalSize) == CGSize(width: 720, height: 1280))
            #expect(receipt.url == draftOutput)
            #expect(receipt.bytes > 0)
            #expect(abs(receipt.duration - duration.seconds) < 0.1)
        }
    }
    @MainActor private func verifyPlayer(_ snapshot: CompositionSnapshot) async throws {
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        item.audioMix = snapshot.audioMix
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        for _ in 0..<50 where item.status == .unknown {
            try await Task.sleep(for: .milliseconds(100))
        }
        player.pause()
        #expect(item.status == .readyToPlay, "Player failed: \(String(describing: item.error))")
    }

}
