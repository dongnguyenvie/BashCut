@preconcurrency import AVFoundation
import BashCutProject
import Crypto
import Foundation
import os

/// Disk-backed ramp audio. Decoding and offline rendering block, so they run on a private serial queue instead
/// of Swift's cooperative executor; the actor only publishes counters.
actor SpeedRampAudioCache {
    private(set) var renders = 0
    private let queue = DispatchQueue(label: "app.bashcut.ramp-audio")

    func render(asset: LoadedAsset, item: Item, mediaFPS: FrameRate, fps: FrameRate, root: URL) async throws -> URL {
        try Task.checkCancellation()
        guard let track = asset.audio, let curve = item.speedCurve else { throw ProjectError.invalid("Missing ramp audio") }
        let key = try cacheKey(asset: asset, item: item, mediaFPS: mediaFPS, fps: fps)
        let job = RampAudioJob(
            asset: asset, track: track, sourceStart: mediaFPS.time(item.sourceIn),
            shape: SpeedRampAudioRenderer.Shape(curve: curve, seconds: fps.time(item.duration).seconds,
                                          preservesPitch: item["preservePitch"] != .bool(false)),
            directory: ProjectCache.url(.rampAudio, projectRoot: root), key: key)
        let flag = CancellationFlag()
        let (url, rendered) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, Bool), any Error>) in
                queue.async { continuation.resume(with: Result { try Self.produce(job, check: flag.check) }) }
            }
        } onCancel: {
            flag.cancel()
        }
        if rendered { renders += 1 }
        return url
    }

    /// Runs on `queue`. Returns whether a new file was rendered rather than found complete on disk.
    private static func produce(_ job: RampAudioJob, check: () throws -> Void) throws -> (URL, Bool) {
        try FileManager.default.createDirectory(at: job.directory, withIntermediateDirectories: true)
        let result = job.directory.appendingPathComponent(job.key + ".caf")
        let count = AVAudioFramePosition(ceil(job.shape.seconds * 48_000))
        if let file = try? AVAudioFile(forReading: result), file.length == count, file.processingFormat.sampleRate == 48_000 {
            return (result, false)
        }
        let scratch = job.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let input = scratch.appendingPathComponent("input.caf"), output = scratch.appendingPathComponent("output.caf")
        try decode(job, to: input, check: check)
        try SpeedRampAudioRenderer.render(input: input, output: output, shape: job.shape, check: check)
        try check()
        // rename(2) replaces an invalid entry atomically; a reader holding the old file keeps its inode, and a
        // concurrent writer of the same key publishes identical content.
        guard rename(output.path, result.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: result.path])
        }
        return (result, true)
    }

    private nonisolated func cacheKey(asset: LoadedAsset, item: Item, mediaFPS: FrameRate, fps: FrameRate) throws -> String {
        let fields: [String: JSONValue] = [
            "version": .integer(7), "source": .string(asset.asset.url.path),
            "modified": .number(asset.signature.modified?.timeIntervalSince1970 ?? 0),
            "size": .integer(asset.signature.size ?? 0), "inode": .string(String(asset.signature.inode ?? 0)),
            "curve": item["speedCurve"] ?? .null, "sourceIn": .integer(item.sourceIn), "duration": .integer(item.duration),
            "mediaFPS": mediaFPS.json, "fps": fps.json, "preservePitch": .bool(item["preservePitch"] != .bool(false))
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(fields)).map { String(format: "%02x", $0) }.joined()
    }

    /// The clip's source span as 48 kHz float PCM, followed by mirrored tail context for the last grains.
    private static func decode(_ job: RampAudioJob, to url: URL, check: () throws -> Void) throws {
        // The composition mixes to stereo; more channels would need an explicit layout for LPCM output.
        let channels = min(2, (job.track.formatDescriptions as? [CMAudioFormatDescription])?.first.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame
        } ?? 1)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: true) else {
            throw ProjectError.invalid("Unsupported ramp audio format")
        }
        let reader = try AVAssetReader(asset: job.asset.asset)
        reader.timeRange = CMTimeRange(
            start: job.sourceStart,
            duration: CMTime(seconds: job.shape.curve.average * job.shape.seconds, preferredTimescale: 600_000))
        let output = AVAssetReaderTrackOutput(track: job.track, outputSettings: format.settings)
        guard reader.canAdd(output) else { throw ProjectError.invalid("Unsupported ramp audio source") }
        reader.add(output)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: true)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Could not decode ramp source") }
        defer { reader.cancelReading() }
        var tail: [Float] = []
        let limit = contextFrames * Int(channels)
        while let sample = output.copyNextSampleBuffer() {
            try check()
            guard let block = CMSampleBufferGetDataBuffer(sample),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample)))
            else { throw ProjectError.invalid("Could not read ramp audio samples") }
            buffer.frameLength = buffer.frameCapacity
            guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData,
                  CMBlockBufferGetDataLength(block) == Int(buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize),
                  CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: CMBlockBufferGetDataLength(block), destination: destination) == noErr
            else { throw ProjectError.invalid("Could not copy ramp audio samples") }
            try file.write(from: buffer)
            let count = Int(buffer.frameLength * channels)
            tail.append(contentsOf: UnsafeBufferPointer(start: destination.assumingMemoryBound(to: Float.self), count: count))
            if tail.count > limit { tail.removeFirst(tail.count - limit) }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Could not finish ramp audio decode") }
        try file.write(from: mirroredContext(tail, format: format))
    }

    private static let contextFrames = 24_000

    /// Pitch processing needs lookahead even for the last output grain. Mirror the clip's own tail as filter
    /// context instead of starving the unit or reading content beyond the user's source out point.
    private static func mirroredContext(_ tail: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let channels = Int(format.channelCount)
        guard !tail.isEmpty, let padding = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(contextFrames)),
              let pointer = padding.mutableAudioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self)
        else { throw ProjectError.invalid("Empty ramp audio source") }
        padding.frameLength = padding.frameCapacity
        let tailFrames = tail.count / channels
        for frame in 0..<contextFrames {
            let phase = frame % (2 * tailFrames)
            let sourceFrame = phase < tailFrames ? tailFrames - 1 - phase : phase - tailFrames
            for channel in 0..<channels { pointer[frame * channels + channel] = tail[sourceFrame * channels + channel] }
        }
        return padding
    }
}

/// One clip's render inputs, resolved on the actor and handed to the blocking queue.
private struct RampAudioJob: @unchecked Sendable {
    let asset: LoadedAsset
    let track: AVAssetTrack
    let sourceStart: CMTime
    let shape: SpeedRampAudioRenderer.Shape
    let directory: URL
    let key: String
}

/// Bridges task cancellation to blocking work running on a dispatch queue.
private final class CancellationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    func cancel() { state.withLock { $0 = true } }
    func check() throws { if state.withLock({ $0 }) { throw CancellationError() } }
}
