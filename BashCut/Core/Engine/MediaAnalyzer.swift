@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics
import Foundation
import VideoToolbox

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
        picture measurePicture: Bool = true, sound measureSound: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MediaAnalysis {
        let asset = AVURLAsset(url: url)
        let tech = try await self.tech(asset, url: url)
        // Sound and picture decode different tracks: read them side by side.
        async let sound = measureSound && tech.audio != nil ? try await self.sound(asset) : nil
        var picture: MediaAnalysis.Picture?
        if measurePicture, tech.video != nil, frames > 0 {
            picture = try await self.picture(
                AVURLAsset(url: pictureURL ?? url), fps: fps, frames: frames, samplesPerSecond: samplesPerSecond,
                source: pictureURL == nil ? "original" : "proxy", progress: progress)
        }
        let measuredSound = try await sound
        return MediaAnalysis(
            key: key, measuredAt: ISO8601DateFormatter().string(from: Date()), tech: tech, picture: picture,
            sound: measuredSound)
    }

    /// One read frame: the review's grey thumbnail plus sharpness and colourfulness.
    struct Frame {
        let grey: [UInt8]
        let sharpness: Double
        let colourfulness: Double
    }

    static func picture(
        _ asset: AVURLAsset, fps: FrameRate, frames: Int, samplesPerSecond: Double, source: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MediaAnalysis.Picture {
        let interval = max(1, Int((fps.value / samplesPerSecond).rounded()))
        let sampleFrames = Array(stride(from: 0, to: frames, by: interval))
        // One decode in order is several times faster than exact-time requests (each decodes from a key frame) and
        // gives every frame, so the cut search below needs no second read. Seeking stays the fallback.
        let decoded = try await self.sequential(
            asset, fps: fps, frames: frames, measured: Set(sampleFrames), progress: progress)
        let read: [Int: Frame]
        if let decoded { read = decoded.measured } else { read = try await self.frames(sampleFrames, asset: asset, fps: fps) }
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
        let grey: (Int) -> [UInt8]?
        if let decoded {
            grey = { $0 >= 0 && $0 < decoded.grey.count ? decoded.grey[$0] : nil }
        } else {
            let between = Set(jumps.flatMap { ($0.0 + 1)..<$0.1 })
            let detail = try await self.frames(between.sorted(), asset: asset, fps: fps).merging(read) { first, _ in first }
            grey = { detail[$0]?.grey }
        }
        var candidates: [MediaAnalysis.Cut] = []
        for (start, end) in jumps {
            let pairs = (start..<end).compactMap { frame -> MediaAnalysis.Cut? in
                guard let left = grey(frame), let right = grey(frame + 1) else { return nil }
                return MediaAnalysis.Cut(frame: frame + 1, score: PictureSampler.difference(left, right))
            }
            if let best = pairs.max(by: { $0.score < $1.score }), best.score >= candidateFloor { candidates.append(best) }
        }
        return MediaAnalysis.Picture(
            fps: fps.value, interval: interval, frames: frames, source: source, samples: samples,
            candidates: candidates, candidateFloor: candidateFloor)
    }

    /// Decodes the video track once, in order, in its native YUV format: a grey thumbnail of every frame from the luma
    /// plane (the cut search compares neighbours) and the full `Frame` of the `measured` ones, scaled to `side` pixels
    /// in hardware and measured like an exact-time image request would be. Each frame index gets the picture shown at
    /// that time (the last decoded frame at or before it). Nil when the track cannot be read this way.
    static func sequential(
        _ asset: AVURLAsset, fps: FrameRate, frames: Int, measured: Set<Int>,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> (grey: [[UInt8]?], measured: [Int: Frame])? {
        guard frames > 0, let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let natural = try await track.load(.naturalSize)
        guard natural.width > 0, natural.height > 0, let scaler = Scaler(natural: natural, side: side),
            let (reader, output) = yuvReader(asset, track: track)
        else { return nil }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var grey = [[UInt8]?](repeating: nil, count: frames)
        var measuredFrames: [Int: Frame] = [:]
        var last: (index: Int, buffer: CVPixelBuffer, grey: [UInt8], frame: Frame?)?
        // Gives the frames from `last` up to `end` the picture of `last`.
        func fill(to end: Int) {
            guard var current = last else { return }
            for index in max(0, current.index)..<min(frames, end) {
                grey[index] = current.grey
                guard measured.contains(index) else { continue }
                if current.frame == nil { current.frame = scaler.frame(current.buffer) }
                measuredFrames[index] = current.frame
            }
            last = current
        }
        var reported = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample), let thumbnail = Self.lumaThumbnail(buffer) else { continue }
            let index = fps.frame(CMSampleBufferGetPresentationTimeStamp(sample))
            if let previous = last, index <= previous.index { continue }
            fill(to: index)
            last = (index, buffer, thumbnail, nil)
            if index >= frames { break }
            if let progress, index - reported >= max(1, frames / 50) {
                reported = index
                progress(Double(index) / Double(frames))
            }
        }
        guard reader.status != .failed, last != nil else { return nil }
        fill(to: frames)
        return (grey, measuredFrames)
    }

    /// A started reader of `track` decoding to 8-bit 4:2:0 YUV, the decoder's own output (no colour conversion).
    static func yuvReader(_ asset: AVURLAsset, track: AVAssetTrack) -> (AVAssetReader, AVAssetReaderTrackOutput)? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let formats = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: formats.map { NSNumber(value: $0) }])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        return reader.startReading() ? (reader, output) : nil
    }

    /// Scales decoded frames to `side` pixels on the long edge as 32BGRA images, for the measured frames.
    final class Scaler {
        let session: VTPixelTransferSession
        let width: Int
        let height: Int

        init?(natural: CGSize, side: Int) {
            var session: VTPixelTransferSession?
            guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session) == noErr,
                let session
            else { return nil }
            let scale = min(1, Double(side) / Double(max(natural.width, natural.height)))
            (self.session, width, height) = (
                session, max(2, Int((natural.width * scale).rounded())), max(2, Int((natural.height * scale).rounded()))
            )
        }

        deinit { VTPixelTransferSessionInvalidate(session) }

        /// The colour space the decoded frame is tagged with, so the scaled image is read like an image request.
        static func colorSpace(of buffer: CVPixelBuffer) -> CGColorSpace? {
            guard let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) else { return nil }
            return CVImageBufferCreateColorSpaceFromAttachments(attachments)?.takeRetainedValue()
        }

        func frame(_ buffer: CVPixelBuffer) -> Frame? {
            var scaled: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &scaled) == kCVReturnSuccess,
                let scaled, VTPixelTransferSessionTransferImage(session, from: buffer, to: scaled) == noErr,
                let image = MediaAnalyzer.image(scaled, colorSpace: Self.colorSpace(of: buffer)),
                let grey = PictureSampler.thumbnail(image)
            else { return nil }
            return Frame(grey: grey, sharpness: sharpness(image), colourfulness: colourfulness(image))
        }
    }

    /// A `PictureSampler.grid`-square grey thumbnail of a YUV frame's luma plane, stretched to full range.
    static func lumaThumbnail(_ buffer: CVPixelBuffer) -> [UInt8]? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard CVPixelBufferIsPlanar(buffer), CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
        else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let (width, height) = (CVPixelBufferGetWidthOfPlane(buffer, 0), CVPixelBufferGetHeightOfPlane(buffer, 0))
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let grid = PictureSampler.grid
        guard width >= grid, height >= grid else { return nil }
        // Each cell is the mean of an evenly spread `taps`×`taps` set of its pixels: a full-HD frame reads about
        // 37k of its 2M luma samples, enough for the cell means that cut scores compare.
        let taps = 8
        let luma = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: grid * grid)
        var cell = 0
        while cell < grid * grid {
            let (cellRow, cellColumn) = (cell / grid, cell % grid)
            var total = 0
            var tapRow = 0
            while tapRow < taps {
                let y = ((cellRow * taps + tapRow) * 2 + 1) * height / (grid * taps * 2)
                let line = luma + y * rowBytes
                var tapColumn = 0
                while tapColumn < taps {
                    total += Int(line[((cellColumn * taps + tapColumn) * 2 + 1) * width / (grid * taps * 2)])
                    tapColumn += 1
                }
                tapRow += 1
            }
            pixels[cell] = UInt8(total / (taps * taps))
            cell += 1
        }
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return pixels }
        return pixels.map { UInt8(max(0, min(255, (Int($0) - 16) * 255 / 219))) }
    }

    /// A copy of a 32BGRA pixel buffer as an image in `colorSpace` (device RGB when nil).
    static func image(_ buffer: CVPixelBuffer, colorSpace: CGColorSpace? = nil) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
            let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let context = CGContext(
            data: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return context?.makeImage()
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
        // Raw pointers and while loops: range iteration costs generic metadata lookups per pixel in debug builds.
        let total = pixels.withUnsafeBufferPointer { pixels -> Int in
            var total = 0
            var row = 1
            while row < height - 1 {
                var index = row * width + 1
                let end = row * width + width - 1
                while index < end {
                    let around = Int(pixels[index - 1]) + Int(pixels[index + 1]) + Int(pixels[index - width])
                        + Int(pixels[index + width])
                    total += abs(4 * Int(pixels[index]) - around)
                    index += 1
                }
                row += 1
            }
            return total
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
