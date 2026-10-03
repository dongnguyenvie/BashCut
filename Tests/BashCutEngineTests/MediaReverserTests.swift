import AVFoundation
import BashCutTestSupport
import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

struct MediaReverserTests {
    /// Grayscale thumbnail of the frame at `seconds`, exact time.
    private static func thumbnail(_ url: URL, at seconds: Double) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixels = [UInt8](repeating: 0, count: 32 * 18)
        let context = try #require(CGContext(
            data: &pixels, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 18))
        return pixels
    }

    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    @Test("The reversed copy starts on the range's last frame and ends on its first, with sound")
    func reverse() async throws {
        let video = try TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("reverse")
        defer { try? FileManager.default.removeItem(at: root) }
        let fps = 30_000.0 / 1_001
        let output = try await MediaReverser.reverse(
            source: video, range: 0.5...1.5, to: root.appendingPathComponent("reversed.mov"), fps: fps)
        #expect(abs(output.frames - 30) <= 1)
        #expect(output.hasAudio)
        let asset = AVURLAsset(url: output.url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)

        let lastSource = try await Self.thumbnail(video, at: 1.5 - 1 / fps)
        let firstSource = try await Self.thumbnail(video, at: 0.5)
        let firstReversed = try await Self.thumbnail(output.url, at: 0)
        let lastReversed = try await Self.thumbnail(output.url, at: Double(output.frames - 1) / fps)
        #expect(Self.difference(firstReversed, lastSource) < Self.difference(firstReversed, firstSource))
        #expect(Self.difference(lastReversed, firstSource) < Self.difference(lastReversed, lastSource))
        #expect(Self.difference(firstReversed, lastSource) < 8)
    }
}
