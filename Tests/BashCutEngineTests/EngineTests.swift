import AVFoundation
import AppKit
import BashCutProject
import BashCutTestSupport
import CoreImage
import SnapshotTesting
import Testing

@testable import BashCutEngine

struct EngineTests {
    private func fixture(count: Int = 2, picture: Bool = true) async throws -> (Project, CompositionSnapshot) {
        _ = try await TestFixtures.requireVideo()
        var project = Project(name: "Synthetic engine fixture")
        let asset = Media(fields: [
            "id": .string("source"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var operations: [EditOperation] = [.addMedia(asset)]
        for index in 0..<count {
            var item = Item(id: "clip-\(index)", media: "source", at: index * 45, duration: 45)
            if !picture { item["opacity"] = .number(0) }
            item["transform"] = .object(["zoom": .number(index.isMultiple(of: 2) ? 1 : 1.25)])
            operations.append(.insert(track: "v1", item: item))
        }
        var caption = Item(id: "caption", at: 0, duration: count * 45)
        caption["text"] = .string("Ăn ngon ở Buôn Ma Thuột\nă â đ ê ô ơ ư ỹ")
        operations.append(.insert(track: "t1", item: caption))
        project = try project.applying(.group(label: "Fixture", author: .user, ops: operations)).project
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        return (project, snapshot)
    }

    @Test("Vietnamese captions match the compositor output before lossy encoding")
    func captionFrame() async throws {
        // Keep the golden independent of ffmpeg versions and H.264 decoder variation in the source fixture.
        // The real compositor still places the caption; video appearance is covered by export/still tests.
        let (project, snapshot) = try await fixture(picture: false)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: project.fps.time(20)).image
        #expect(image.width == 1080 && image.height == 1920)
        assertSnapshot(
            of: NSImage(cgImage: image, size: CGSize(width: 1080, height: 1920)),
            as: .image(precision: 0.999, perceptualPrecision: 0.98), named: "vietnamese-caption",
            record: ProcessInfo.processInfo.environment["BASHCUT_RECORD_SNAPSHOTS"] == "1" ? .all : .never
        )
    }

    @Test("Generated composition becomes ready in AVPlayer")
    @MainActor func playerReadiness() async throws {
        let (_, snapshot) = try await fixture()
        #expect(snapshot.videoComposition.customVideoCompositorClass == BashCutCompositor.self)
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        item.audioMix = snapshot.audioMix
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        defer { player.pause() }
        let deadline = ContinuousClock.now + .seconds(5)
        while item.status == .unknown, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(item.status == .readyToPlay, "Player failed: \(String(describing: item.error))")
    }

    @Test("H.264 exports retain size, duration, audio and visible picture")
    func export() async throws {
        let performance = ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"
        let (project, snapshot) = try await fixture(count: performance ? 20 : 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = ContinuousClock.now
        let output = directory.appendingPathComponent("export.mp4")
        try await Exporter().export(snapshot, to: output)
        let elapsed = start.duration(to: .now)
        let rendered = AVURLAsset(url: output)
        let duration = try await rendered.load(.duration)
        #expect(abs(duration.seconds - Double(project.duration) / project.fps.value) < 0.1)
        #expect(try await rendered.loadTracks(withMediaType: .audio).count == 1)
        let track = try #require(try await rendered.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        let generator = AVAssetImageGenerator(asset: rendered)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: project.fps.time(20)).image
        try verifyNonBlack(image)
        if performance {
            #expect(elapsed < .seconds(duration.seconds), "Synthetic export must be faster than real time: \(elapsed)")
        } else {
            try await verifyDraft(project, directory: directory, duration: duration.seconds)
        }
    }

    private func verifyNonBlack(_ image: CGImage) throws {
        let source = CIImage(cgImage: image)
        let average = try #require(CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: source, kCIInputExtentKey: CIVector(cgRect: source.extent),
        ])?.outputImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        #expect(pixel.prefix(3).contains { $0 > 10 }, "Exported picture must not be black")
    }

    private func verifyDraft(_ project: Project, directory: URL, duration: Double) async throws {
        var draft = project
        var format = draft["format"]?.object ?? [:]
        format["width"] = .integer(720)
        format["height"] = .integer(1280)
        draft["format"] = .object(format)
        let snapshot = try await CompositionBuilder().build(draft, root: TestFixtures.mediaRoot)
        let output = directory.appendingPathComponent("draft.mp4")
        let receipt = try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 720, height: 1280))
        #expect(receipt.url == output)
        #expect(receipt.bytes > 0)
        #expect(abs(receipt.duration - duration) < 0.1)
    }
}
