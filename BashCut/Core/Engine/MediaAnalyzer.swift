@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation

/// Measures one source file for `media.analyze` (P0-A1): file facts, picture samples with exact-frame cut candidates,
/// and sound levels. Picture values come from the same thumbnail functions as the timeline review
/// (`PictureSampler`), so a source file and the timeline are measured alike.
public enum MediaAnalyzer {
    /// Sample-to-sample change at which the frames in between are searched for a cut.
    public static let candidateFloor = 0.04
    /// Long edge of the frames read for sharpness; thumbnails are made from the same frame.
    static let side = 256

    /// A content key: SHA-256 of the size and the first and last mebibyte, with the measurement version. A moved or
    /// renamed file keeps its key; an edited one gets a new key.
    public static func key(for url: URL) throws -> String {
        try ProjectCache.contentKey(for: url, namespace: "media-analysis-v\(MediaAnalysis.version)")
    }

    /// The stored record for `key` in the project's analysis cache, if any and of this version.
    public static func load(key: String, projectRoot: URL) -> MediaAnalysis? {
        guard let record = ProjectCache.record(MediaAnalysis.self, .analysis, key: key, projectRoot: projectRoot),
            record.version == MediaAnalysis.version, record.key == key
        else { return nil }
        return record
    }

    public static func save(_ record: MediaAnalysis, projectRoot: URL) throws {
        try ProjectCache.store(record, .analysis, key: record.key, projectRoot: projectRoot)
    }

    /// Measures `url`. `pictureURL` (a proxy with the same timing) is read for the picture when given; `fps` and
    /// `frames` are the media's, so source frames match the project's.
    public static func measure(
        _ url: URL, key: String, fps: FrameRate, frames: Int, pictureURL: URL? = nil, samplesPerSecond: Double = 4,
        picture measurePicture: Bool = true, sound measureSound: Bool = true
    ) async throws -> MediaAnalysis {
        let asset = AVURLAsset(url: url)
        let tech = try await self.tech(asset, url: url)
        var picture: MediaAnalysis.Picture?
        if measurePicture, tech.video != nil, frames > 0 {
            picture = try await self.picture(
                AVURLAsset(url: pictureURL ?? url), fps: fps, frames: frames, samplesPerSecond: samplesPerSecond,
                source: pictureURL == nil ? "original" : "proxy")
        }
        let sound = measureSound && tech.audio != nil ? try await self.sound(asset) : nil
        return MediaAnalysis(
            key: key, measuredAt: ISO8601DateFormatter().string(from: Date()), tech: tech, picture: picture, sound: sound)
    }

    /// One read frame: the review's grey thumbnail plus sharpness and colourfulness.
    struct Frame {
        let grey: [UInt8]
        let sharpness: Double
        let colourfulness: Double
    }

    static func picture(
        _ asset: AVURLAsset, fps: FrameRate, frames: Int, samplesPerSecond: Double, source: String
    ) async throws -> MediaAnalysis.Picture {
        let interval = max(1, Int((fps.value / samplesPerSecond).rounded()))
        let sampleFrames = Array(stride(from: 0, to: frames, by: interval))
        let read = try await self.frames(sampleFrames, asset: asset, fps: fps)
        var samples: [MediaAnalysis.Sample] = []
        var previous: Frame?
        for frame in sampleFrames {
            guard let current = read[frame] else { continue }
            let (luma, spread) = PictureSampler.statistics(current.grey)
            samples.append(MediaAnalysis.Sample(
                frame: frame, luma: luma, spread: spread,
                change: previous.map { PictureSampler.difference($0.grey, current.grey) } ?? 1,
                peak: previous.map { PictureSampler.peakDifference($0.grey, current.grey) } ?? 1,
                sharpness: current.sharpness, colourfulness: current.colourfulness))
            previous = current
        }
        // A jump between two samples is searched frame by frame: a cut puts the whole change on one frame pair,
        // movement spreads it over the interval.
        let jumps = zip(samples, samples.dropFirst()).filter { $1.change >= candidateFloor }.map { ($0.frame, $1.frame) }
        let between = Set(jumps.flatMap { ($0.0 + 1)..<$0.1 })
        let detail = try await self.frames(between.sorted(), asset: asset, fps: fps)
            .merging(read) { first, _ in first }
        var candidates: [MediaAnalysis.Cut] = []
        for (start, end) in jumps {
            let pairs = (start..<end).compactMap { frame -> MediaAnalysis.Cut? in
                guard let left = detail[frame], let right = detail[frame + 1] else { return nil }
                return MediaAnalysis.Cut(frame: frame + 1, score: PictureSampler.difference(left.grey, right.grey))
            }
            if let best = pairs.max(by: { $0.score < $1.score }), best.score >= candidateFloor { candidates.append(best) }
        }
        return MediaAnalysis.Picture(
            fps: fps.value, interval: interval, frames: frames, source: source, samples: samples,
            candidates: candidates, candidateFloor: candidateFloor)
    }

    /// Reads `frames` exactly; a frame that cannot be decoded is left out.
    static func frames(_ frames: [Int], asset: AVURLAsset, fps: FrameRate) async throws -> [Int: Frame] {
        guard !frames.isEmpty else { return [:] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var result: [Int: Frame] = [:]
        for await image in generator.images(for: frames.map(fps.time)) {
            try Task.checkCancellation()
            guard let picture = try? image.image, let grey = PictureSampler.thumbnail(picture) else { continue }
            result[fps.frame(image.requestedTime)] = Frame(
                grey: grey, sharpness: sharpness(picture), colourfulness: colourfulness(picture))
        }
        return result
    }

    /// Mean absolute 4-neighbour Laplacian of the grey frame at its read size, as a fraction of full scale.
    static func sharpness(_ image: CGImage) -> Double {
        let (width, height) = (image.width, image.height)
        guard width > 2, height > 2 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var total = 0
        for row in 1..<(height - 1) {
            for column in 1..<(width - 1) {
                let index = row * width + column
                let around = Int(pixels[index - 1]) + Int(pixels[index + 1]) + Int(pixels[index - width])
                    + Int(pixels[index + width])
                total += abs(4 * Int(pixels[index]) - around)
            }
        }
        return Double(total) / Double((width - 2) * (height - 2)) / 255
    }

    /// Hasler–Süsstrunk colourfulness, sqrt(σrg² + σyb²) + 0.3·sqrt(μrg² + μyb²), on a 24×24 RGB thumbnail with
    /// channels as fractions of full scale.
    static func colourfulness(_ image: CGImage) -> Double {
        let grid = PictureSampler.grid
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: grid, height: grid, bitsPerComponent: 8, bytesPerRow: grid * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        guard drawn else { return 0 }
        var rg: [Double] = []
        var yb: [Double] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let (red, green, blue) = (Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255)
            rg.append(red - green)
            yb.append((red + green) / 2 - blue)
        }
        func meanAndDeviation(_ values: [Double]) -> (Double, Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            return (mean, (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot())
        }
        let (meanRG, deviationRG) = meanAndDeviation(rg)
        let (meanYB, deviationYB) = meanAndDeviation(yb)
        return (deviationRG * deviationRG + deviationYB * deviationYB).squareRoot()
            + 0.3 * (meanRG * meanRG + meanYB * meanYB).squareRoot()
    }
}
