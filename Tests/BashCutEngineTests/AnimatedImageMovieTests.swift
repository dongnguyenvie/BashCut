import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

/// Animated stickers play as movies with alpha; effect previews are animated GIFs.
struct AnimatedImageMovieTests {
    /// A `size`×`size` frame, transparent except a square whose shade is `shade`.
    private static func frame(_ shade: CGFloat, size: Int = 40) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: shade, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        return try #require(context.makeImage())
    }

    @Test("A GIF's frames and delays become a looped ProRes 4444 movie of the same timing")
    func gifToMovie() async throws {
        let folder = try TestFixtures.temporaryDirectory("animated-sticker")
        defer { try? FileManager.default.removeItem(at: folder) }
        let gif = folder.appendingPathComponent("spin.gif")
        try AnimatedImageMovie.writeGIF([try Self.frame(0.1), try Self.frame(0.5), try Self.frame(0.9)], delay: 0.2, to: gif)
        let delays = try #require(AnimatedImageMovie.delays(of: gif))
        #expect(delays.count == 3)
        #expect(delays.allSatisfy { abs($0 - 0.2) < 0.001 })
        #expect(AnimatedImageMovie.loops(covering: 5, loopSeconds: 0.6) == 9)
        #expect(AnimatedImageMovie.loops(covering: 0.1, loopSeconds: 0.6) == 1)
        #expect(AnimatedImageMovie.loops(covering: 10_000, loopSeconds: 0.6) == 1_000)

        let movie = folder.appendingPathComponent("spin.x2.mov")
        let seconds = try await AnimatedImageMovie.write(image: gif, loops: 2, to: movie)
        #expect(abs(seconds - 1.2) < 0.001)
        let asset = AVURLAsset(url: movie)
        #expect(abs(try await asset.load(.duration).seconds - 1.2) < 0.01)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AppleProRes4444)
        #expect(try await track.load(.naturalSize) == CGSize(width: 40, height: 40))

        // A still image is not animated.
        let still = folder.appendingPathComponent("still.gif")
        try AnimatedImageMovie.writeGIF([try Self.frame(0.3)], delay: 0.1, to: still)
        #expect(AnimatedImageMovie.delays(of: still) == nil)
        await #expect(throws: (any Error).self) { try await AnimatedImageMovie.write(image: still, to: movie) }
    }

    @Test("An effect preview's frames keep the clip's pace within bounds")
    func previewDelay() {
        #expect(abs(EffectPreviewGIF.delay(seconds: 1.2, frames: 12) - 0.1) < 1e-9)
        #expect(EffectPreviewGIF.delay(seconds: 0.2, frames: 12) == 0.05)
        #expect(EffectPreviewGIF.delay(seconds: 60, frames: 12) == 0.25)
        #expect(EffectPreviewGIF.delay(seconds: 1, frames: 0) == 0.1)
    }
}
