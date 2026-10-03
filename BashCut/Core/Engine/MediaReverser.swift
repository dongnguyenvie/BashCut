@preconcurrency import AVFoundation
import Foundation

/// Writes a reversed copy of part of a media file (CapCut's Reverse): the picture played backwards and the sound
/// reversed, as H.264 + AAC in a .mov at the source's size, orientation and frame rate.
///
/// Video is decoded in short windows from the end of the range (each window needs its own reader, which starts at
/// the keyframe before it), so memory holds one window of frames, not the whole clip.
public enum MediaReverser {
    public struct Output: Sendable {
        public let url: URL
        public let frames: Int
        public let hasAudio: Bool
    }

    /// Frames per decoded window.
    static let window = 12

    /// Reverses `range` (seconds) of `source` into `destination` (replaced if it exists). `progress` gets 0…1.
    public static func reverse(
        source: URL, range: ClosedRange<Double>, to destination: URL, fps: Double,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Output {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReverseError("The clip has no picture to reverse")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let rate = try await video.load(.estimatedDataRate)
        let frameDuration = CMTime(value: 1_000, timescale: CMTimeScale((fps * 1_000).rounded()))
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600_000)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600_000)
        guard end > start else { throw ReverseError("Nothing to reverse") }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(min(max(Double(rate), 8_000_000), 60_000_000))],
        ])
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        writer.add(videoInput)

        var audioFrames: AudioSource?
        var audioInput: AVAssetWriterInput?
        if let audio {
            let reversed = try await AudioSource(track: audio, asset: asset, start: start, end: end)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: reversed.sampleRate,
                AVNumberOfChannelsKey: reversed.channels, AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioFrames = reversed
            audioInput = input
        }
        guard writer.startWriting() else { throw ReverseError(writer.error?.localizedDescription ?? "Cannot write") }
        writer.startSession(atSourceTime: .zero)

        let frames = VideoSource(asset: asset, track: video, start: start, end: end, window: window)
        let expected = max(1, Int(((end - start).seconds * fps).rounded()))
        let written = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                try await pump(videoInput, label: "video") {
                    guard let buffer = try frames.next() else { return nil }
                    let time = CMTimeMultiply(frameDuration, multiplier: Int32(frames.emitted - 1))
                    guard adaptor.append(buffer, withPresentationTime: time) else {
                        throw ReverseError(writer.error?.localizedDescription ?? "Cannot write a frame")
                    }
                    progress(min(0.99, Double(frames.emitted) / Double(expected)))
                    return ()
                }
                return frames.emitted
            }
            if let audioInput, let audioFrames {
                group.addTask {
                    try await pump(audioInput, label: "audio") {
                        guard let buffer = try audioFrames.next() else { return nil }
                        guard audioInput.append(buffer) else {
                            throw ReverseError(writer.error?.localizedDescription ?? "Cannot write sound")
                        }
                        return ()
                    }
                    return 0
                }
            }
            return try await group.reduce(0, +)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ReverseError(writer.error?.localizedDescription ?? "Writing failed") }
        progress(1)
        return Output(url: destination, frames: written, hasAudio: audioInput != nil)
    }

    /// Feeds `input` from `next` whenever it is ready, until `next` returns nil.
    private static func pump(
        _ input: AVAssetWriterInput, label: String, next: @escaping @Sendable () throws -> Void?
    ) async throws {
        let queue = DispatchQueue(label: "app.bashcut.reverse.\(label)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finished = Flag()
            input.requestMediaDataWhenReady(on: queue) {
                guard !finished.value else { return }
                do {
                    while input.isReadyForMoreMediaData {
                        guard try next() != nil else {
                            finished.value = true
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                } catch {
                    finished.value = true
                    input.markAsFinished()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public struct ReverseError: LocalizedError {
    public let message: String
    init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private final class Flag: @unchecked Sendable {
    var value = false
}

/// Decoded frames of a range, newest first: windows of `window` frames read from the end backwards.
private final class VideoSource: @unchecked Sendable {
    let asset: AVAsset
    let track: AVAssetTrack
    let start: CMTime
    var windowEnd: CMTime
    let window: Int
    var pending: [CVPixelBuffer] = []
    var emitted = 0
    private let frameSpan: CMTime

    init(asset: AVAsset, track: AVAssetTrack, start: CMTime, end: CMTime, window: Int) {
        self.asset = asset
        self.track = track
        self.start = start
        windowEnd = end
        self.window = window
        let fps = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
        frameSpan = CMTime(seconds: Double(window) / fps, preferredTimescale: 600_000)
    }

    func next() throws -> CVPixelBuffer? {
        while pending.isEmpty {
            guard windowEnd > start else { return nil }
            let windowStart = CMTimeMaximum(start, windowEnd - frameSpan)
            pending = try decode(from: windowStart, to: windowEnd)
            windowEnd = windowStart
        }
        emitted += 1
        return pending.removeLast()
    }

    /// Frames whose presentation time is in [from, to), oldest first, copied out of the decoder's pool.
    private func decode(from: CMTime, to: CMTime) throws -> [CVPixelBuffer] {
        let reader = try AVAssetReader(asset: asset)
        // A reader emits the frame showing at its range start stamped with that start time; starting two frames
        // early keeps that partial copy outside [from, to).
        let lead = CMTimeMultiplyByRatio(frameSpan, multiplier: 2, divisor: Int32(window))
        reader.timeRange = CMTimeRange(start: CMTimeMaximum(.zero, from - lead), end: to)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw ReverseError(reader.error?.localizedDescription ?? "Cannot read the clip") }
        var frames: [CVPixelBuffer] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time >= from, time < to, let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(try copy(image))
        }
        if reader.status == .failed { throw ReverseError(reader.error?.localizedDescription ?? "Cannot read the clip") }
        return frames
    }

    private func copy(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, CVPixelBufferGetWidth(source), CVPixelBufferGetHeight(source), CVPixelBufferGetPixelFormatType(source),
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
        guard let result else { throw ReverseError("Out of memory while reversing") }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(result, [])
        defer {
            CVPixelBufferUnlockBaseAddress(result, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        for plane in 0..<max(1, CVPixelBufferGetPlaneCount(source)) {
            guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                let to = CVPixelBufferGetBaseAddressOfPlane(result, plane)
            else { continue }
            let rows = CVPixelBufferGetHeightOfPlane(source, plane)
            let fromStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let toStride = CVPixelBufferGetBytesPerRowOfPlane(result, plane)
            let bytes = min(fromStride, toStride)
            for row in 0..<rows { memcpy(to + row * toStride, from + row * fromStride, bytes) }
        }
        return result
    }
}

/// The range's sound as float PCM, reversed, handed out as sample buffers of 4096 frames.
private final class AudioSource: @unchecked Sendable {
    let sampleRate: Double
    let channels: Int
    private var samples: [Float]
    private var offset = 0
    private let format: CMAudioFormatDescription
    private static let chunk = 4_096

    init(track: AVAssetTrack, asset: AVAsset, start: CMTime, end: CMTime) async throws {
        let description = try await track.load(.formatDescriptions).first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        sampleRate = basic.map { $0.mSampleRate > 0 ? $0.mSampleRate : 48_000 } ?? 48_000
        channels = max(1, min(2, Int(basic?.mChannelsPerFrame ?? 2)))
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: start, end: end)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw ReverseError(reader.error?.localizedDescription ?? "Cannot read sound") }
        var interleaved: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            interleaved += chunk
        }
        // Reverse whole frames so channels stay in place.
        let count = interleaved.count / channels
        var reversed = [Float](repeating: 0, count: count * channels)
        for frame in 0..<count {
            for channel in 0..<channels {
                reversed[frame * channels + channel] = interleaved[(count - 1 - frame) * channels + channel]
            }
        }
        samples = reversed
        var stream = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var created: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &stream, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &created)
        guard let created else { throw ReverseError("Cannot describe the sound") }
        format = created
    }

    func next() throws -> CMSampleBuffer? {
        let total = samples.count / channels
        guard offset < total else { return nil }
        let frames = min(Self.chunk, total - offset)
        let bytes = frames * channels * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let block else { throw ReverseError("Out of memory while reversing sound") }
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress! + offset * channels * 4, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &buffer)
        offset += frames
        guard let buffer else { throw ReverseError("Cannot hand sound to the writer") }
        return buffer
    }
}
