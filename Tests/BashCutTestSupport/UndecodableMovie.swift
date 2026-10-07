@preconcurrency import AVFoundation
import Foundation

/// A QuickTime movie whose video uses a codec no Mac decodes (`bczz`): it opens and has a video track of the
/// given size and length, but AVFoundation fails every frame with "Cannot Decode", like VP9 without its decoder.
public enum UndecodableMovie {
    public static let codec = "bczz"

    public static func write(to destination: URL, frames: Int = 30, width: Int32 = 320, height: Int32 = 180) async throws {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: 0x6263_7A7A, width: width, height: height, extensions: nil,
            formatDescriptionOut: &format) == noErr, let format
        else { throw failure("No format description") }
        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Cannot start") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            let sample = try sample(frame: frame, format: format)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            guard input.append(sample) else { throw writer.error ?? failure("Frame \(frame) rejected") }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? failure("Incomplete movie") }
    }

    /// 64 opaque bytes standing in for one compressed frame, 1/30 s long.
    private static func sample(frame: Int, format: CMVideoFormatDescription) throws -> CMSampleBuffer {
        let length = 64
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
            let block
        else { throw failure("No block buffer") }
        let bytes = [UInt8](repeating: UInt8(frame & 0xFF), count: length)
        _ = bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(
            with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(frame), timescale: 30),
            decodeTimeStamp: .invalid)
        var size = length
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
            let sample
        else { throw failure("No sample buffer") }
        return sample
    }

    private static func failure(_ reason: String) -> TestFixtures.Missing {
        TestFixtures.Missing(description: "Undecodable movie: \(reason)")
    }
}
