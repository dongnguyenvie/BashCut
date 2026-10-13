@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// A clone reference cut from a source (#532): the chosen window in source seconds, its checks and the WAV written.
public struct VoiceCloneTrim: Sendable {
    public let start: Double
    public let end: Double
    public let checks: [VoiceCloneCheck]
    public let output: URL
    /// The source was longer than the scanned part (the first `VoiceCloneAudio.longestScan` seconds of the range).
    public let scannedSeconds: Double
    public var seconds: Double { end - start }
}

/// Reads a source's sound as mono samples and writes the chosen window as a clone reference WAV (#532).
public enum VoiceCloneAudio {
    /// Samples per second the source is read at and the reference is written at.
    public static let rate = 24_000.0
    /// At most this many seconds of a source are scanned.
    public static let longestScan = 300.0

    /// Trims `range` of `source` (the whole file when nil) to the best window within [minSeconds, maxSeconds] and
    /// writes it to `output` as 16-bit mono WAV; throws `VoiceCloneRefusal` when no window is good enough.
    public static func trim(
        source: URL, range: ClosedRange<Double>?, minSeconds: Double, maxSeconds: Double, output: URL,
        classify: Bool = true
    ) async throws -> VoiceCloneTrim {
        let start = max(0, range?.lowerBound ?? 0)
        let samples = try await decode(source, from: start, seconds: min(longestScan, range.map { $0.upperBound - start } ?? longestScan))
        // Speech and music from the on-device sound classifier; levels alone when it cannot run.
        let classes = classify ? try? await classification(samples) : nil
        let window = try VoiceCloneTrimmer.choose(
            samples, rate: rate, minSeconds: minSeconds, maxSeconds: maxSeconds, classes: classes)
        let first = Int(window.start * rate), last = min(samples.count, Int(window.end * rate))
        try write(Array(samples[first..<last]), to: output)
        return VoiceCloneTrim(
            start: start + window.start, end: start + window.end, checks: window.checks, output: output,
            scannedSeconds: Double(samples.count) / rate)
    }

    /// The sound classifier's speech and music per frame, run off the caller's thread (it waits for its results).
    public static func classification(_ samples: [Float]) async throws -> VoiceCloneClassification? {
        try await Task.detached(priority: .userInitiated) { try VoiceCloneClassifier.classify(samples, rate: rate) }.value
    }

    /// Mono float samples at `rate` of the first sound track, from `from` for at most `seconds`.
    public static func decode(_ url: URL, from: Double, seconds: Double) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ProjectError.invalid("\(url.lastPathComponent) has no sound")
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 48_000),
            duration: CMTime(seconds: max(0.05, seconds), preferredTimescale: 48_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw ProjectError.invalid("Cannot read the sound of \(url.lastPathComponent)") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(buffer)
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw ProjectError.invalid("Cannot read the sound") }
            data.withUnsafeBytes { samples.append(contentsOf: $0.bindMemory(to: Float.self)) }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        return samples
    }

    /// Writes mono samples at `rate` as a 16-bit WAV file.
    public static func write(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { throw ProjectError.invalid("Cannot write the voice reference") }
        for (index, value) in samples.enumerated() { channel[index] = value }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            ],
            commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
