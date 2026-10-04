@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Still images (photos, PNG stickers, illustrations) on the timeline. AVFoundation compositions only take
/// movie tracks, so the engine reads each image through a one-frame ProRes 4444 movie (alpha kept) at
/// `.bashcut/stills/<media id>.mov`, made on first use and again whenever the image file changes. Items hold that
/// frame for their whole length, like a freeze frame; the project keeps referencing the image itself.
public enum StillImageMovie {
    public static let folder = ".bashcut/stills"
    /// The single sample's length in the movie; items scale it to their duration.
    public static let sampleDuration = CMTime(value: 1, timescale: 30)
    /// Longer side of the movie frame. Larger photos are scaled down; enough for a 4K export and a 1.5× zoom on 1080p.
    public static let maximumSide = 4096

    public static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// Pixel size of an image after its EXIF orientation, or nil when it cannot be read.
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The image decoded with its orientation applied, its longer side at most `maximumSide`.
    public static func decoded(_ url: URL, maximumSide: Int = maximumSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The still movie for `media`, written from `image` when it is missing or older than the image.
    public static func movie(for media: Media, image: URL, root: URL) async throws -> URL {
        guard ProxyMediaSource.isSafe(media.id) else { throw ProjectError.invalid("Invalid media ID \(media.id)") }
        let destination = root.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(media.id).appendingPathExtension("mov")
        let manager = FileManager.default
        guard manager.fileExists(atPath: image.path) else {
            throw ProjectError.invalid("Image is missing: \(media.path)")
        }
        if let made = modified(destination), let source = modified(image), made >= source { return destination }
        try await write(image: image, to: destination)
        return destination
    }

    /// Writes one ProRes 4444 frame through a temporary file, so a failed run leaves nothing behind.
    static func write(image: URL, to destination: URL) async throws {
        guard let picture = decoded(image) else {
            throw ProjectError.invalid("Cannot read the image \(image.lastPathComponent)")
        }
        // ProRes wants even dimensions; the frame is stretched by at most one pixel.
        let width = max(2, picture.width + picture.width % 2), height = max(2, picture.height + picture.height % 2)
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
        guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Cannot write the still") }
        writer.startSession(atSourceTime: .zero)
        let buffer = try pixelBuffer(picture, width: width, height: height)
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard adaptor.append(buffer, withPresentationTime: .zero) else {
            writer.cancelWriting()
            throw writer.error ?? ProjectError.invalid("Cannot write the still")
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: sampleDuration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Cannot write the still") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    static func pixelBuffer(_ picture: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary, &created)
        guard let buffer = created else { throw ProjectError.invalid("Cannot allocate the still frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw ProjectError.invalid("Cannot draw the still frame") }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func modified(_ url: URL) -> Date? {
        // Not URL.resourceValues: a URL instance caches them, and the caller may pass the same one again.
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
