@preconcurrency import AVFoundation
import Foundation

/// Native, deterministic test footage: 60 moving BGRA frames at 30000/1001 and a 48 kHz sine tone.
/// Generated at runtime; no command-line codec, downloaded media or user files are involved.
public enum SyntheticMovie {
    public static func write(to destination: URL) async throws {
        try Task.checkCancellation()
        let root = try TestFixtures.temporaryDirectory("native-movie")
        defer { try? FileManager.default.removeItem(at: root) }
        let tone = root.appendingPathComponent("tone.caf")
        let duration = CMTime(value: 60 * 1001, timescale: 30000)
        try TestFixtures.writeTone(to: tone, seconds: duration.seconds,
                                   tone: .init(frequency: 440, amplitude: 0.125))
        let asset = AVURLAsset(url: tone)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw failure("No tone track") }
        let reader = try AVAssetReader(asset: asset)
        let source = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        source.alwaysCopiesSampleData = false
        reader.add(source)
        let movie = root.appendingPathComponent("movie.mp4")
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false]
        ])
        video.mediaTimeScale = 30000
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000
        ])
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? failure("Cannot start") }
        writer.startSession(atSourceTime: .zero)
        do {
            try await append(writer: writer, video: video, pixels: pixels, audio: audio, source: source)
            guard reader.status == .completed else { throw reader.error ?? failure("Incomplete audio") }
            writer.endSession(atSourceTime: duration)
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? failure("Incomplete movie") }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: movie, to: destination)
        } catch {
            reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
            throw error
        }
    }

    private static func append(writer: AVAssetWriter, video: AVAssetWriterInput,
                               pixels: AVAssetWriterInputPixelBufferAdaptor, audio: AVAssetWriterInput,
                               source: AVAssetReaderTrackOutput) async throws {
        var frame = 0, audioFinished = false
        let deadline = ContinuousClock.now + .seconds(30)
        while frame < 60 || !audioFinished {
            try Task.checkCancellation()
            guard writer.status == .writing, ContinuousClock.now < deadline else {
                throw writer.error ?? failure("Writer stalled")
            }
            var advanced = false
            if frame < 60, video.isReadyForMoreMediaData {
                let buffer = try picture(frame: frame)
                guard pixels.append(buffer, withPresentationTime: CMTime(value: Int64(frame * 1001), timescale: 30000)) else {
                    throw writer.error ?? failure("Cannot append picture")
                }
                frame += 1
                if frame == 60 { video.markAsFinished() }
                advanced = true
            }
            if !audioFinished, audio.isReadyForMoreMediaData {
                if let sample = source.copyNextSampleBuffer() {
                    guard audio.append(sample) else { throw writer.error ?? failure("Cannot append tone") }
                } else {
                    audio.markAsFinished()
                    audioFinished = true
                }
                advanced = true
            }
            // Only yield under backpressure. This short fixture never sleeps between ready samples.
            if !advanced { try await Task.sleep(for: .milliseconds(1)) }
        }
    }

    private static func picture(frame: Int) throws -> CVPixelBuffer {
        var value: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, nil, &value)
        guard result == kCVReturnSuccess, let buffer = value else { throw failure("Cannot allocate picture") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw failure("Cannot access picture")
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<180 {
            for x in 0..<320 {
                let offset = y * stride + x * 4
                bytes[offset] = UInt8(20 + x % 190)
                bytes[offset + 1] = UInt8(40 + y)
                bytes[offset + 2] = UInt8(30 + frame * 3)
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    private static func failure(_ reason: String) -> TestFixtures.Missing {
        TestFixtures.Missing(description: "Synthetic movie: \(reason)")
    }
}
