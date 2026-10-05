import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

struct AnimatedImageTests {
    /// A 40×20 GIF of `frames` frames, 0.25 s each: the left half opaque red, the right half transparent.
    private func writeGIF(to url: URL, frames: Int) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
        for _ in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.clear(CGRect(x: 0, y: 0, width: 40, height: 20))
            context.setFillColor(try #require(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]] as CFDictionary
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties)
        }
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("An animated GIF becomes a looped movie with alpha; a one-frame image is not animated")
    func animatedMovie() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let gif = folder.appendingPathComponent("wave.gif")
        try writeGIF(to: gif, frames: 4)
        let still = folder.appendingPathComponent("still.gif")
        try writeGIF(to: still, frames: 1)
        #expect(AnimatedImageMovie.isAnimated(gif))
        #expect(!AnimatedImageMovie.isAnimated(still))

        let movie = folder.appendingPathComponent("stickers/wave.mov")
        try await AnimatedImageMovie.write(image: gif, to: movie)
        let asset = AVURLAsset(url: movie)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        // One loop is 1 s, so six loops reach the minimum length.
        #expect(abs(try await asset.load(.duration).seconds - AnimatedImageMovie.minimumSeconds) < 0.01)
        #expect(try await track.load(.naturalSize) == CGSize(width: 40, height: 20))
        #expect(abs(try await track.load(.nominalFrameRate) - 4) < 0.01)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_AppleProRes4444)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        var samples = 0
        var first: CVPixelBuffer?
        while let sample = output.copyNextSampleBuffer() {
            if first == nil { first = CMSampleBufferGetImageBuffer(sample) }
            samples += 1
        }
        #expect(samples == 24)
        let buffer = try #require(first)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        func alpha(x: Int) -> UInt8 { base[10 * rowBytes + x * 4 + 3] }
        #expect(alpha(x: 5) == 255)
        #expect(alpha(x: 35) == 0)
    }
}
