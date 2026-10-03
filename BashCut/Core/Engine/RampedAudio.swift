@preconcurrency import AVFoundation
import BashCutProject
import CryptoKit
import Foundation

/// Disk-backed ramp audio. Actor isolation serializes cache publication and keeps offline rendering off the UI actor.
actor RampedAudio {
    private(set) var renders = 0

    func render(asset: LoadedAsset, item: Item, mediaFPS: FrameRate, fps: FrameRate, root: URL) throws -> URL {
        try Task.checkCancellation()
        guard let source = asset.audio, let curve = item.speedCurve else { throw ProjectError.invalid("Missing ramp audio") }
        let key = try cacheKey(asset: asset, item: item, mediaFPS: mediaFPS, fps: fps)
        let directory = root.appendingPathComponent(".bashcut/ramped-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = directory.appendingPathComponent(key + ".caf")
        let seconds = fps.time(item.duration).seconds
        let count = AVAudioFramePosition(ceil(seconds * 48_000))
        if let file = try? AVAudioFile(forReading: result), file.length == count, file.processingFormat.sampleRate == 48_000 {
            return result
        }
        let scratch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let input = scratch.appendingPathComponent("input.caf"), output = scratch.appendingPathComponent("output.caf")
        try decode(asset: asset.asset, track: source, to: input, start: mediaFPS.time(item.sourceIn),
                   duration: CMTime(seconds: curve.average * seconds, preferredTimescale: 600_000))
        try OfflineAudioRamp.render(input: input, output: output, curve: curve, seconds: seconds,
                                    preservesPitch: item["preservePitch"] != .bool(false))
        try Task.checkCancellation()
        // An invalid/truncated cache entry can be replaced; publication happens only after the complete render.
        if FileManager.default.fileExists(atPath: result.path) { try FileManager.default.removeItem(at: result) }
        try FileManager.default.moveItem(at: output, to: result)
        renders += 1
        return result
    }

    private func cacheKey(asset: LoadedAsset, item: Item, mediaFPS: FrameRate, fps: FrameRate) throws -> String {
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

    private func decode(asset: AVAsset, track: AVAssetTrack, to url: URL, start: CMTime, duration: CMTime) throws {
        let channels = (track.formatDescriptions as? [CMAudioFormatDescription])?.first.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame
        } ?? 1
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: true) else {
            throw ProjectError.invalid("Unsupported ramp audio format")
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: start, duration: duration)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: format.settings)
        reader.add(output)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: true)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Could not decode ramp source") }
        defer { reader.cancelReading() }
        var tail: [Float] = []
        let contextFrames = 24_000
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
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
            if tail.count > contextFrames * Int(channels) { tail.removeFirst(tail.count - contextFrames * Int(channels)) }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Could not finish ramp audio decode") }
        // Pitch processing needs lookahead even for the last output grain. Mirror the clip's own tail as
        // filter context instead of starving the unit or reading content beyond the user's source out point.
        guard !tail.isEmpty, let padding = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(contextFrames)),
              let pointer = padding.mutableAudioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self)
        else { throw ProjectError.invalid("Empty ramp audio source") }
        padding.frameLength = padding.frameCapacity
        let tailFrames = tail.count / Int(channels)
        for frame in 0..<contextFrames {
            let phase = frame % (2 * tailFrames)
            let sourceFrame = phase < tailFrames ? tailFrames - 1 - phase : phase - tailFrames
            for channel in 0..<Int(channels) { pointer[frame * Int(channels) + channel] = tail[sourceFrame * Int(channels) + channel] }
        }
        try file.write(from: padding)
    }
}
