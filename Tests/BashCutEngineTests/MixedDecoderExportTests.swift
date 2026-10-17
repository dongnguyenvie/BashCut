import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing
import VideoToolbox

@testable import BashCutEngine

/// An 8-bit H.264 clip right after a 10-bit HEVC HLG clip on one layer once failed the export at the join with
/// "source frame missing": both shared one composition track, and AVFoundation gave the compositor no picture for
/// the second clip (the other way round worked). Clips whose pictures decode differently now get lanes of their own.
/// The failure needed real camera files (a 30 s Sony HLG clip used to its end, then a phone H.264 clip); these
/// generated clips export either way, so the test checks the lanes the fix gives them and that the export finishes.
struct MixedDecoderExportTests {
    @Test("An H.264 clip after a 10-bit HLG HEVC clip exports every frame")
    func hdrThenSDR() async throws {
        let directory = try TestFixtures.temporaryDirectory("mixed-decoders")
        defer { try? FileManager.default.removeItem(at: directory) }
        let hlg = directory.appendingPathComponent("hlg.mov"), sdr = directory.appendingPathComponent("sdr.mov")
        try await Self.write(to: hlg, hdr: true)
        try await Self.write(to: sdr, hdr: false)
        let first = try await SourceEdgeMovie.media(hlg, id: "hlg", count: .pictures)
        let second = try await SourceEdgeMovie.media(sdr, id: "sdr", count: .pictures)
        var project = try Project(name: "Mixed", fps: FrameRate(30, 1)).applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(first), .addMedia(second),
            .insert(track: "v1", item: Item(id: "a", media: "hlg", at: 0, duration: 30)),
            .insert(track: "v1", item: Item(id: "b", media: "sdr", at: 30, duration: 20)),
        ])).project
        project["format"] = .object([
            "width": .integer(320), "height": .integer(180), "fps": FrameRate(30, 1).json, "sampleRate": .integer(48000),
        ])
        let snapshot = try await CompositionBuilder().build(project, root: directory)
        let tracks = snapshot.composition.tracks(withMediaType: .video)
        #expect(tracks.count == 2, "the two clips decode differently and do not share a track")
        let output = directory.appendingPathComponent("mixed.mp4")
        try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try DeliveredQC.frameTimes(asset, track: track).count == 50)
    }

    @Test("Clips that decode alike share a lane; a different decoder takes another")
    func lanes() throws {
        let composition = AVMutableComposition()
        var lanes = VideoCompositionLanes()
        let first = try lanes.take(layer: "v1", start: 0, end: 10, decoder: "avc1", composition: composition)
        let second = try lanes.take(layer: "v1", start: 10, end: 20, decoder: "avc1", composition: composition)
        let third = try lanes.take(layer: "v1", start: 20, end: 30, decoder: "hvc1 10 HLG", composition: composition)
        let fourth = try lanes.take(layer: "v1", start: 30, end: 40, decoder: "avc1", composition: composition)
        #expect(first.trackID == second.trackID && second.trackID == fourth.trackID)
        #expect(third.trackID != first.trackID)
    }

    /// 30 pictures of 160 × 90: 10-bit HEVC tagged BT.2020 HLG when `hdr`, else 8-bit H.264.
    private static func write(to url: URL, hdr: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [AVVideoWidthKey: 160, AVVideoHeightKey: 90]
        let format: OSType
        if hdr {
            settings[AVVideoCodecKey] = AVVideoCodecType.hevc
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ]
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAllowFrameReorderingKey: true,
            ]
            format = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        } else {
            settings[AVVideoCodecKey] = AVVideoCodecType.h264
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoAllowFrameReorderingKey: true,
            ]
            format = kCVPixelFormatType_32BGRA
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = 30
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var value: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, format, nil, &value)
            let buffer = try #require(value)
            CVPixelBufferLockBaseAddress(buffer, [])
            let planes = max(1, CVPixelBufferGetPlaneCount(buffer))
            for plane in 0..<planes {
                let base = CVPixelBufferGetPlaneCount(buffer) == 0
                    ? CVPixelBufferGetBaseAddress(buffer) : CVPixelBufferGetBaseAddressOfPlane(buffer, plane)
                let bytes = CVPixelBufferGetPlaneCount(buffer) == 0
                    ? CVPixelBufferGetBytesPerRow(buffer) * 90
                    : CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane)
                // Noise that changes every picture, so the encoder reorders frames as camera footage does.
                let bytesPointer = try #require(base).assumingMemoryBound(to: UInt8.self)
                var seed = UInt32(index * 7919 + plane + 1)
                for offset in 0..<bytes {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    bytesPointer[offset] = UInt8(truncatingIfNeeded: 40 + (seed >> 24) % 160)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
    }
}
