import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

import BashCutEngine

/// Movies shaped like camera files whose picture and sound do not line up: sound running past the last picture, or
/// the first picture arriving after the sound starts.
enum SourceEdgeMovie {
    struct Shape {
        var pictures = 60
        /// One picture's length; 1001/30000 is 29.97 fps.
        var frame = CMTime(value: 1001, timescale: 30000)
        /// When the first picture starts.
        var videoStart = CMTime.zero
        var audioSeconds = 2.0
    }

    static func write(_ shape: Shape, to url: URL) async throws {
        let scratch = try TestFixtures.temporaryDirectory("edge-movie")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let tone = scratch.appendingPathComponent("tone.caf")
        try TestFixtures.writeTone(to: tone, seconds: shape.audioSeconds, tone: .init(frequency: 440, amplitude: 0.125))
        let toneAsset = AVURLAsset(url: tone)
        guard let toneTrack = try await toneAsset.loadTracks(withMediaType: .audio).first else { throw failure("tone") }
        let reader = try AVAssetReader(asset: toneAsset)
        let source = AVAssetReaderTrackOutput(track: toneTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(source)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
        ])
        video.mediaTimeScale = shape.frame.timescale
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
        ])
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? failure("start") }
        writer.startSession(atSourceTime: .zero)
        try await append(shape, writer: writer, pixels: pixels, audio: audio, source: source)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? failure("finish") }
    }

    private static func append(
        _ shape: Shape, writer: AVAssetWriter, pixels: AVAssetWriterInputPixelBufferAdaptor,
        audio: AVAssetWriterInput, source: AVAssetReaderTrackOutput
    ) async throws {
        let video = pixels.assetWriterInput
        var picture = 0, audioDone = false
        let deadline = ContinuousClock.now + .seconds(30)
        while picture < shape.pictures || !audioDone {
            guard writer.status == .writing, ContinuousClock.now < deadline else { throw writer.error ?? failure("stall") }
            var advanced = false
            if picture < shape.pictures, video.isReadyForMoreMediaData {
                let time = shape.videoStart + CMTimeMultiply(shape.frame, multiplier: Int32(picture))
                guard pixels.append(try buffer(picture), withPresentationTime: time) else {
                    throw writer.error ?? failure("picture")
                }
                picture += 1
                if picture == shape.pictures { video.markAsFinished() }
                advanced = true
            }
            if !audioDone, audio.isReadyForMoreMediaData {
                if let sample = source.copyNextSampleBuffer() {
                    guard audio.append(sample) else { throw writer.error ?? failure("audio") }
                } else {
                    audio.markAsFinished()
                    audioDone = true
                }
                advanced = true
            }
            if !advanced { try await Task.sleep(for: .milliseconds(1)) }
        }
    }

    /// Where a media record's `frames` comes from: the container duration (projects imported before #437) or the
    /// last picture (`MediaFrames`, what import records now).
    enum Count: String, CaseIterable, CustomTestStringConvertible {
        case duration, pictures
        var testDescription: String { rawValue }
    }

    /// The media record import makes (`ProjectDocument.importedMedia`).
    static func media(_ url: URL, id: String = "m", count: Count = .duration) async throws -> Media {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw failure("no video") }
        let nominal = Double(try await video.load(.nominalFrameRate))
        let fps: FrameRate = abs(nominal - 29.97) < 0.02 ? FrameRate()
            : abs(nominal - 23.976) < 0.02 ? FrameRate(24000, 1001) : FrameRate(Int(nominal.rounded()), 1)
        let frames = switch count {
        case .duration: Int((try await asset.load(.duration).seconds * fps.value).rounded(.down))
        case .pictures: try await MediaFrames.sourceFrames(of: asset, fps: fps)
        }
        return Media(fields: [
            "id": .string(id), "path": .string(url.lastPathComponent), "kind": .string("video"),
            "fps": fps.json, "frames": .integer(frames), "hasAudio": .bool(true),
        ])
    }

    private static func buffer(_ index: Int) throws -> CVPixelBuffer {
        var value: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA, nil, &value) == kCVReturnSuccess,
              let buffer = value else { throw failure("pixels") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw failure("pixels")
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<90 {
            for column in 0..<160 {
                let offset = row * stride + column * 4
                bytes[offset] = 200
                bytes[offset + 1] = UInt8(60 + index % 100)
                bytes[offset + 2] = 120
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    private static func failure(_ reason: String) -> Failure { Failure(description: "Source edge movie: \(reason)") }
}
