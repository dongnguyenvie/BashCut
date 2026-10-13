@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Animated images (GIF, APNG, animated WebP) as stickers that move: AVFoundation plays only movies, so an animated
/// sticker is turned into a ProRes 4444 movie (alpha kept) with each frame held for its own delay, repeated `loops`
/// times. Also writes animated GIF previews from still frames (an effect preset's preview in the library).
public enum AnimatedImageMovie {
    /// Longer side of a sticker movie's frame; larger animations are scaled down.
    public static let maximumSide = 1024
    /// The longest movie a sticker is looped to.
    public static let maximumSeconds = 600.0
    /// A frame delay at or under this is played at `defaultDelay`, like browsers do.
    static let shortestDelay = 0.011
    static let defaultDelay = 0.1

    /// Each frame's delay in seconds, or nil when the file is not an image with more than one frame.
    public static func delays(of url: URL) -> [Double]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        return (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let delay = frameDelay(properties)
            return delay > shortestDelay ? delay : defaultDelay
        }
    }

    private static func frameDelay(_ properties: [CFString: Any]) -> Double {
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (container, unclamped, clamped) in containers {
            guard let values = properties[container] as? [CFString: Any] else { continue }
            if let delay = (values[unclamped] as? NSNumber)?.doubleValue, delay > 0 { return delay }
            if let delay = (values[clamped] as? NSNumber)?.doubleValue { return delay }
        }
        return 0
    }

    /// How many loops of an animation `loopSeconds` long cover `seconds` (at least one, at most `maximumSeconds`).
    public static func loops(covering seconds: Double, loopSeconds: Double) -> Int {
        guard loopSeconds > 0, seconds.isFinite else { return 1 }
        let most = max(1, Int(maximumSeconds / loopSeconds))
        return min(most, max(1, Int((seconds / loopSeconds - 1e-9).rounded(.up))))
    }

    /// Writes the animation `image` as a ProRes 4444 movie at `destination`, `loops` times over; returns its length
    /// in seconds. Written through a temporary file, so a failed run leaves nothing behind.
    @discardableResult
    public static func write(image: URL, loops: Int = 1, to destination: URL, maximumSide: Int = maximumSide) async throws
        -> Double
    {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil), let delays = delays(of: image) else {
            throw ProjectError.invalid("\(image.lastPathComponent) is not an animated image")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide, kCGImageSourceShouldCacheImmediately: true,
        ]
        var frames: [CGImage] = []
        for index in delays.indices {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                throw ProjectError.invalid("Cannot read frame \(index + 1) of \(image.lastPathComponent)")
            }
            frames.append(frame)
        }
        let first = frames[0]
        let width = max(2, first.width + first.width % 2), height = max(2, first.height + first.height % 2)
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial.mov")
        defer { try? FileManager.default.removeItem(at: partial) }

        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Cannot write the sticker movie") }
        writer.startSession(atSourceTime: .zero)
        let buffers = try frames.map { try pixelBuffer($0, width: width, height: height) }
        let timescale: CMTimeScale = 6_000
        var time = 0.0
        for _ in 0..<max(1, loops) {
            for (index, buffer) in buffers.enumerated() {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
                let at = CMTime(seconds: time, preferredTimescale: timescale)
                guard adaptor.append(buffer, withPresentationTime: at) else {
                    writer.cancelWriting()
                    throw writer.error ?? ProjectError.invalid("Cannot write the sticker movie")
                }
                time += delays[index]
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: timescale))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Cannot write the sticker movie") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return time
    }

    /// Writes `frames` as a looping animated GIF, each shown `delay` seconds, scaled so the longer side is at most
    /// `maximumSide`.
    public static func writeGIF(_ frames: [CGImage], delay: Double, to destination: URL, maximumSide: Int = 320) throws {
        guard !frames.isEmpty else { throw ProjectError.invalid("No frames for the animated preview") }
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw ProjectError.invalid("Cannot write \(destination.lastPathComponent)") }
        CGImageDestinationSetProperties(output, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(output, scaled(frame, maximumSide: maximumSide), properties) }
        guard CGImageDestinationFinalize(output) else {
            throw ProjectError.invalid("Cannot write \(destination.lastPathComponent)")
        }
    }

    private static func scaled(_ image: CGImage, maximumSide: Int) -> CGImage {
        let side = max(image.width, image.height)
        guard side > maximumSide else { return image }
        let scale = Double(maximumSide) / Double(side)
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func pixelBuffer(_ picture: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary, &created)
        guard let buffer = created else { throw ProjectError.invalid("Cannot allocate a sticker frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw ProjectError.invalid("Cannot draw a sticker frame") }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

/// The animated preview an effect preset saved from a clip gets: a few frames across the clip.
public enum EffectPreviewGIF {
    public static let frames = 12

    /// Each frame's delay: the clip's pace, kept between 0.05 and 0.25 s so a short clip stays visible and a long
    /// one does not crawl.
    public static func delay(seconds: Double, frames: Int) -> Double {
        guard frames > 0, seconds.isFinite, seconds > 0 else { return 0.1 }
        return min(0.25, max(0.05, seconds / Double(frames)))
    }
}
