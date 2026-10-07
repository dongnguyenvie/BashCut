@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics

/// Measures the composited timeline for the picture review (#432): brightness, flatness and change at a fixed
/// interval, and the difference across each hard cut on Main. Frames are rendered small (`side` pixels on the long
/// edge) and compared as grey thumbnails, so a 3-minute edit takes a few hundred small renders.
public enum PictureSampler {
    /// Grey thumbnail width and height the comparisons use.
    static let grid = 24

    /// With `range`, only the samples and cuts inside it (`review.verify`, P1-E3); samples stay on the same grid.
    public static func measure(
        _ snapshot: CompositionSnapshot, project: Project, samplesPerSecond: Double = 2, side: Int = 96,
        range: Range<Int>? = nil
    ) async throws -> ReviewPicture {
        let interval = max(1, Int((project.fps.value / samplesPerSecond).rounded()))
        let duration = project.duration
        let span = range.map { max(0, $0.lowerBound)..<min(duration, $0.upperBound) } ?? 0..<duration
        let first = span.lowerBound - span.lowerBound % interval
        let sampleFrames = Array(stride(from: first, to: span.upperBound, by: interval))
        let cuts = ReviewPicture.hardCuts(project).filter { $0.at < duration && span.contains($0.at) }
        let frames = Set(sampleFrames + cuts.flatMap { [$0.before, $0.at] }).sorted()
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var thumbnails: [Int: [UInt8]] = [:]
        let times = frames.map { project.fps.time($0) }
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            let frame = Int((result.requestedTime.seconds * project.fps.value).rounded())
            // A frame the compositor cannot draw counts as black, like the empty picture it would export.
            thumbnails[frame] = (try? result.image).flatMap(thumbnail) ?? [UInt8](repeating: 0, count: grid * grid)
        }
        var samples: [ReviewPicture.Sample] = []
        var previous: [UInt8]?
        for frame in sampleFrames {
            guard let pixels = thumbnails[frame] else { continue }
            let (luma, spread) = statistics(pixels)
            samples.append(ReviewPicture.Sample(
                frame: frame, luma: luma, spread: spread, change: previous.map { difference($0, pixels) } ?? 1,
                peak: previous.map { peakDifference($0, pixels) } ?? 1))
            previous = pixels
        }
        var differences: [String: Double] = [:]
        for cut in cuts {
            guard let before = thumbnails[cut.before], let after = thumbnails[cut.at] else { continue }
            differences[cut.item] = difference(before, after)
        }
        return ReviewPicture(revision: project.revision, interval: interval, samples: samples, cuts: differences)
    }

    /// The image as a `grid`×`grid` grey thumbnail.
    static func thumbnail(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: grid * grid)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: grid, height: grid, bitsPerComponent: 8, bytesPerRow: grid,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Mean and standard deviation, as fractions of full scale.
    static func statistics(_ pixels: [UInt8]) -> (mean: Double, spread: Double) {
        guard !pixels.isEmpty else { return (0, 0) }
        let values = pixels.map { Double($0) / 255 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return (mean, variance.squareRoot())
    }

    /// The largest difference of one cell, as a fraction of full scale.
    static func peakDifference(_ left: [UInt8], _ right: [UInt8]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 1 }
        return Double(zip(left, right).map { abs(Int($0) - Int($1)) }.max() ?? 0) / 255
    }

    /// Mean absolute difference, as a fraction of full scale.
    static func difference(_ left: [UInt8], _ right: [UInt8]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 1 }
        let total = zip(left, right).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(left.count) / 255
    }
}
