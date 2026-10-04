@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO

/// Animated images (GIF, APNG, animated WebP) on the timeline. A still image is held as one frame
/// (`StillImageMovie`); an animated one is written once, at import, as a ProRes 4444 movie (alpha kept) that
/// repeats the animation, and the project references that movie like any other clip.
public enum AnimatedImageMovie {
    /// Project folder that takes the movies made at import.
    public static let folder = "stickers"
    /// Longer side of the movie frame; animated stickers are small.
    public static let maximumSide = 1080
    /// The animation repeats whole loops until the movie is at least this long, so a short loop can be trimmed
    /// to a useful length.
    public static let minimumSeconds = 6.0
    /// Upper bound on written frames, whatever the loop length.
    public static let maximumFrames = 900
    private static let timescale: CMTimeScale = 600

    public static func isAnimated(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// Seconds each frame of the animation is shown. Delays under 11 ms are read as 100 ms, as browsers do.
    static func delays(of source: CGImageSource) -> [Double] {
        let keys: [(dictionary: CFString, unclamped: CFString, clamped: CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        return (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            for key in keys {
                guard let values = properties[key.dictionary] as? [CFString: Any] else { continue }
                let delay = (values[key.unclamped] as? Double) ?? (values[key.clamped] as? Double) ?? 0
                return delay < 0.011 ? 0.1 : delay
            }
            return 0.1
        }
    }

    /// Writes the animation as a ProRes 4444 movie through a temporary file, so a failed run leaves nothing behind.
    public static func write(image: URL, to destination: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil), CGImageSourceGetCount(source) > 1,
            let first = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ProjectError.invalid("Cannot read the animated image \(image.lastPathComponent)") }
        let delays = delays(of: source)
        let loop = delays.reduce(0, +)
        let loops = max(1, min(Int((minimumSeconds / loop).rounded(.up)), maximumFrames / delays.count))
        let scale = min(1, Double(maximumSide) / Double(max(first.width, first.height)))
        // ProRes wants even dimensions; the frame is stretched by at most one pixel.
        let scaledWidth = Int((Double(first.width) * scale).rounded()), scaledHeight = Int((Double(first.height) * scale).rounded())
        let width = max(2, scaledWidth + scaledWidth % 2), height = max(2, scaledHeight + scaledHeight % 2)
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
        guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Cannot write the animation") }
        writer.startSession(atSourceTime: .zero)
        var time = CMTime.zero
        for _ in 0..<loops {
            for (index, delay) in delays.enumerated() {
                guard let picture = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    writer.cancelWriting()
                    throw ProjectError.invalid("Cannot read the animated image \(image.lastPathComponent)")
                }
                let buffer = try StillImageMovie.pixelBuffer(picture, width: width, height: height)
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    writer.cancelWriting()
                    throw writer.error ?? ProjectError.invalid("Cannot write the animation")
                }
                time = time + CMTime(seconds: delay, preferredTimescale: timescale)
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: time)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Cannot write the animation") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}
