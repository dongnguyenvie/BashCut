import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing

@testable import BashCutEngine

/// A 29.97 fps clip joined to a 30 fps clip once exported one frame short at the join (59 of 60, memo
/// 2026-10-07-75). Each generated picture is a flat grey whose level is its index (`8 + 4 × index`), so the export's
/// frames can be followed one by one across the join.
struct JoinedRatesExportTests {
    @Test("A 29.97 fps clip joined to a 30 fps clip exports every frame, each picture in order", arguments: [
        FrameRate(30, 1), FrameRate(30_000, 1_001),
    ])
    func join(projectRate: FrameRate) async throws {
        let directory = try TestFixtures.temporaryDirectory("joined-rates")
        defer { try? FileManager.default.removeItem(at: directory) }
        let ntsc = directory.appendingPathComponent("ntsc.mov"), whole = directory.appendingPathComponent("whole.mov")
        try await Self.writeRamp(to: ntsc, frame: CMTime(value: 1001, timescale: 30000))
        try await Self.writeRamp(to: whole, frame: CMTime(value: 1, timescale: 30))
        let first = try await SourceEdgeMovie.media(ntsc, id: "a", count: .pictures)
        let second = try await SourceEdgeMovie.media(whole, id: "b", count: .pictures)
        #expect(first.fps == FrameRate(30_000, 1_001) && second.fps == FrameRate(30, 1))
        let joined = try Self.project(projectRate, ops: [
            .addMedia(first), .addMedia(second),
            // Source pictures 0…29 of the 29.97 clip, then 30…59 of the 30 fps clip.
            .insert(track: "v1", item: Item(id: "a", media: "a", at: 0, duration: 30)),
            .insert(track: "v1", item: Item(id: "b", media: "b", at: 30, duration: 30, sourceIn: 30)),
        ])
        // The reference: pictures 0…59 of the 30 fps clip alone, through the same render, encode and decode.
        let reference = try Self.project(projectRate, ops: [
            .addMedia(second), .insert(track: "v1", item: Item(id: "b", media: "b", at: 0, duration: 60)),
        ])
        let (levels, times) = try await Self.export(joined, directory: directory, name: "joined")
        let (ladder, _) = try await Self.export(reference, directory: directory, name: "reference")
        #expect(times.count == 60, "frames written: \(times.count)")
        let step = 1 / projectRate.value
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        #expect(gaps.allSatisfy { abs($0 - step) < 0.6 / 600 + 0.001 }, "\(gaps)")
        #expect(ladder.count == 60 && levels.count == 60)
        // Each frame shows its own picture: the nearest grey of the reference is the one at the same frame. A dropped
        // or held picture shifts the frames after it by one.
        let shown = levels.map { level in ladder.indices.min { abs(ladder[$0] - level) < abs(ladder[$1] - level) } ?? -1 }
        let wrong = shown.enumerated().filter { $0.offset != $0.element }
        #expect(wrong.isEmpty, "frame → picture shown: \(wrong.map { ($0.offset, $0.element) }); levels \(levels)")
    }

    private static func project(_ rate: FrameRate, ops: [EditOperation]) throws -> Project {
        var project = try Project(name: "Join", fps: rate).applying(.group(label: "Fixture", author: .user, ops: ops))
            .project
        project["format"] = .object([
            "width": .integer(320), "height": .integer(180), "fps": rate.json, "sampleRate": .integer(48000),
        ])
        return project
    }

    /// Exports `project` and reads back each frame's grey level and time, in presentation order.
    private static func export(_ project: Project, directory: URL, name: String) async throws -> ([Int], [Double]) {
        let snapshot = try await CompositionBuilder().build(project, root: directory)
        let output = directory.appendingPathComponent(name + ".mp4")
        try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        return (try greens(asset, track: track), try DeliveredQC.frameTimes(asset, track: track).sorted())
    }

    /// 90 flat grey pictures, level `8 + 4 × index` (up to 244 for picture 59; the rest stay at 244).
    private static func writeRamp(to url: URL, frame: CMTime) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
        ])
        input.mediaTimeScale = frame.timescale
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var value: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA, nil, &value)
            let buffer = try #require(value)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try #require(CVPixelBufferGetBaseAddress(buffer))
            memset(base, Int32(min(244, 8 + 4 * index)), CVPixelBufferGetBytesPerRow(buffer) * 90)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            #expect(adaptor.append(buffer, withPresentationTime: CMTimeMultiply(frame, multiplier: Int32(index))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
    }

    /// The green value at the centre of every decoded frame, in presentation order.
    private static func greens(_ asset: AVAsset, track: AVAssetTrack) throws -> [Int] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CancellationError() }
        var values: [(time: Double, green: Int)] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { continue }
            let row = CVPixelBufferGetBytesPerRow(pixels)
            let center = (CVPixelBufferGetHeight(pixels) / 2) * row + (CVPixelBufferGetWidth(pixels) / 2) * 4
            values.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds, Int(base[center + 1])))
        }
        return values.sorted { $0.time < $1.time }.map(\.green)
    }
}
