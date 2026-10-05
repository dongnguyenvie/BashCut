@preconcurrency import AVFoundation
import BashCutProject
import Crypto
import Foundation

public struct AudioWaveform: Codable, Sendable, Equatable {
    public let duration: Double
    public let peaks: [Float]
    public let hasAudio: Bool

    public init(duration: Double, peaks: [Float], hasAudio: Bool = true) {
        self.duration = duration
        self.peaks = peaks
        self.hasAudio = hasAudio
    }

    public func peak(from start: Double, to end: Double) -> Float {
        guard duration > 0, !peaks.isEmpty, start.isFinite, end.isFinite,
            end > start, end > 0, start < duration
        else { return 0 }
        let first = min(peaks.count - 1, Int(max(0, start) / duration * Double(peaks.count)))
        let last = min(peaks.count - 1, Int(min(duration, end) / duration * Double(peaks.count)))
        return peaks[first...max(first, last)].max() ?? 0
    }

    var valid: Bool {
        duration.isFinite && duration > 0 && !peaks.isEmpty && peaks.count <= 20000
            && peaks.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// Bounded stereo peak envelopes. Analysis and disk I/O never run on the UI actor.
public actor WaveformAnalyzer {
    private var memory: [String: AudioWaveform] = [:]
    public init() {}

    public func waveform(url: URL, cacheDirectory: URL? = nil) async throws -> AudioWaveform {
        // URL resource values can be cached on the URL instance; stat fresh metadata on every request.
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (values[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (values[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = "waveform-v2|\(url.standardizedFileURL.path)|\(size)|\(modified)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        if let cached = memory[key] { return cached }
        let cacheURL = cacheDirectory?.appendingPathComponent(key + ".json")
        if let cacheURL, let cached = readCache(cacheURL) {
            remember(cached, key: key)
            return cached
        }
        let result = try await analyze(url)
        try Task.checkCancellation()
        remember(result, key: key)
        if let cacheURL {
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(result) { try? data.write(to: cacheURL, options: .atomic) }
        }
        return result
    }

    private func remember(_ waveform: AudioWaveform, key: String) {
        if memory.count >= 48 { memory.removeAll(keepingCapacity: true) }
        memory[key] = waveform
    }
    private func readCache(_ url: URL) -> AudioWaveform? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 2 * 1024 * 1024),
            let cached = try? JSONDecoder().decode(AudioWaveform.self, from: data), cached.valid
        else { return nil }
        return cached
    }
    private func analyze(_ url: URL) async throws -> AudioWaveform {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ProjectError.invalid("Cannot analyze audio duration") }
        let count = Int(min(20000, max(1, ceil(duration * 100))))
        var peaks = [Float](repeating: 0, count: count)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return AudioWaveform(duration: duration, peaks: peaks, hasAudio: false)
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { throw ProjectError.invalid("Cannot decode waveform audio") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Cannot read waveform audio") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try accumulate(sample, peaks: &peaks, duration: duration)
        }
        guard reader.status == .completed else {
            throw reader.error ?? ProjectError.invalid("Waveform decoding failed")
        }
        return AudioWaveform(duration: duration, peaks: peaks)
    }

    private func accumulate(_ sample: CMSampleBuffer, peaks: inout [Float], duration: Double) throws {
        guard let buffer = CMSampleBufferGetDataBuffer(sample) else { return }
        let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard start.isFinite else { return }
        let length = CMBlockBufferGetDataLength(buffer)
        guard length > 0 else { return }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw ProjectError.invalid("Cannot read waveform PCM") }
        data.withUnsafeBytes { bytes in
            for index in 0..<(length / MemoryLayout<Float>.size) {
                let time = start + Double(index / 2) / 8000
                guard time >= 0, time < duration else { continue }
                let value = abs(bytes.loadUnaligned(fromByteOffset: index * MemoryLayout<Float>.size, as: Float.self))
                guard value.isFinite else { continue }
                let bucket = min(peaks.count - 1, Int(time / duration * Double(peaks.count)))
                peaks[bucket] = max(peaks[bucket], min(1, value))
            }
        }
    }
}
