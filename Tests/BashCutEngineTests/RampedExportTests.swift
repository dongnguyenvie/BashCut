import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreImage
import Foundation
import Testing
@testable import BashCutEngine

@MainActor
struct RampedExportTests {
    @Test("Ramped picture and continuous audio play and export through native AVFoundation", arguments: [true, false])
    func playerAndExport(preservesPitch: Bool) async throws {
        let video = try await TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("ramp-export")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: video, to: root.appendingPathComponent("video.mp4"))
        let media = Media(fields: ["id": .string("m"), "path": .string("video.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59), "hasAudio": .bool(true)])
        var item = Item(id: "a", media: "m", at: 0, duration: 30)
        item["preservePitch"] = .bool(preservesPitch)
        let project = try Project(name: "Export").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: item),
            .setSpeedCurve(item: "a", curve: try #require(SpeedCurve.preset("hero")), keepDuration: true)
        ])).project
        let engine = AVFoundationRenderEngine(source: OriginalMediaSource())
        let preview = try await engine.build(project, root: root, purpose: .preview)
        let playerItem = AVPlayerItem(asset: preview.composition)
        playerItem.videoComposition = preview.videoComposition
        playerItem.audioMix = preview.audioMix
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        defer { player.replaceCurrentItem(with: nil) }
        for _ in 0..<500 where playerItem.status == .unknown { try await Task.sleep(for: .milliseconds(10)) }
        #expect(playerItem.status == .readyToPlay)
        #expect(await player.seek(to: project.fps.time(15), toleranceBefore: .zero, toleranceAfter: .zero))
        let exported = try await engine.build(project, root: root, purpose: .export)
        let url = root.appendingPathComponent("ramp.mp4")
        _ = try await Exporter().export(exported, to: url)
        let measurement = root.appendingPathComponent("ramp.caf")
        _ = try await Exporter().exportAudio(exported, to: measurement)
        let pcm = try await TestFixtures.decodeStereo(measurement)
        #expect(abs(Double(pcm[0].count) / 48000 - project.fps.time(30).seconds) < 0.001)
        let result = AVURLAsset(url: url)
        #expect(abs(try await result.load(.duration).seconds - project.fps.time(30).seconds) < 0.05)
        #expect(try await result.loadTracks(withMediaType: .video).count == 1)
        #expect(try await result.loadTracks(withMediaType: .audio).count == 1)
        let generator = AVAssetImageGenerator(asset: result)
        let picture = try await generator.image(at: project.fps.time(15)).image
        let image = CIImage(cgImage: picture)
        let average = try #require(CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)
        ])?.outputImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        #expect(pixel.prefix(3).contains { $0 > 10 })
    }
}
