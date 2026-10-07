import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

public struct VisionError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// The pictures `vision.faces` and `vision.text` look at (P2-H6, P2-H7): one every `step` source seconds over
/// from…to, upright (the file's rotation applied), at most `maximumPixels` on the long side. A still image is one
/// picture at second 0.
public enum VisionFrames {
    public static let maximumSamples = 3_600

    /// A file and which source seconds of it to look at; nil from/to are its start and end.
    public struct Sampling: Sendable {
        public let path: String
        public let from: Double?
        public let to: Double?
        public let step: Double

        public init(path: String, from: Double? = nil, to: Double? = nil, step: Double) {
            self.path = path
            self.from = from
            self.to = to
            self.step = step
        }
    }

    /// Source seconds sampled from `from` up to (not including) `to`, every `step`; at least `from`.
    public static func seconds(from: Double, to: Double, step: Double) throws -> [Double] {
        guard from.isFinite, to.isFinite, step.isFinite, step > 0, from >= 0, to >= from else {
            throw VisionError("from, to and step must be finite with 0 ≤ from ≤ to and step > 0")
        }
        let count = max(1, Int(((to - from) / step).rounded(.up)))
        guard count <= maximumSamples else {
            throw VisionError("\(count) pictures over \(maximumSamples): use a larger step or a shorter range")
        }
        return (0..<count).map { ((from + Double($0) * step) * 1_000).rounded() / 1_000 }
    }

    /// Calls `body` with each sampled picture and the source second it actually shows.
    public static func forEach(
        _ sampling: Sampling, maximumPixels: Int, _ body: (Double, CGImage) throws -> Void
    ) async throws {
        let url = URL(fileURLWithPath: sampling.path)
        let step = sampling.step
        if let image = still(url, maximumPixels: maximumPixels) {
            try body(0, image)
            return
        }
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw VisionError("The file has no picture")
        }
        let duration = try await asset.load(.duration).seconds
        let start = min(sampling.from ?? 0, duration), end = min(sampling.to ?? duration, duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixels, height: maximumPixels)
        // Within half a step is close enough to the asked second and far cheaper than an exact decode.
        let tolerance = CMTime(seconds: step / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        for second in try seconds(from: start, to: end, step: step) {
            try Task.checkCancellation()
            let (image, actual) = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600))
            try body((actual.seconds * 1_000).rounded() / 1_000, image)
        }
    }

    /// An image file, upright, or nil for anything else (a movie).
    static func still(_ url: URL, maximumPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source) as String?, !type.contains("movie"), !type.contains("mpeg"),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ] as CFDictionary)
    }
}
