@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// Whether a rendered file's sound stays in time with the timeline (P0-B2, `review.sync --rendered`): the level
/// envelope of the export and of the timeline's own mix (10 ms windows) are matched window by window, so each window
/// gives the lag of the render (positive = later) and how well the two match; a lag that grows over the file is
/// drift. Facts only.
public enum RenderDrift {
    static let rate = 100.0
    static let sampleRate = 16_000.0

    /// RMS level in dB per 10 ms of `asset`'s sound (within `range` when given), through `mix` when given; nil when
    /// it has none.
    public static func envelope(_ asset: AVAsset, mix: AVAudioMix?, range: CMTimeRange? = nil) async throws -> [Float]? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: asset)
        if let range { reader.timeRange = range }
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.audioMix = mix
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        let window = Int(sampleRate / rate)
        var levels: [Float] = []
        var sum: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            for sample in samples {
                sum += sample * sample
                count += 1
                if count == window {
                    levels.append(10 * log10(max(sum / Float(window), 1e-10)))
                    sum = 0
                    count = 0
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        return levels
    }

    public struct Window: Sendable, Equatable {
        public let at: Double
        public let lagMs: Double
        public let correlation: Double
    }

    /// For each `window`-second stretch of `reference`, the lag of `rendered` (within ±`maxLag` s) with the highest
    /// normalized correlation of the mean-removed dB envelopes. Stretches without level change (silence) are skipped.
    public static func windows(
        reference: [Float], rendered: [Float], window: Double = 10, maxLag: Double = 0.5
    ) -> [Window] {
        let size = Int(window * rate), reach = Int(maxLag * rate)
        guard size > 0 else { return [] }
        var result: [Window] = []
        var start = 0
        while start + size <= reference.count {
            let part = Array(reference[start..<start + size])
            let mean = part.reduce(0, +) / Float(size)
            let centred = part.map { $0 - mean }
            let energy = centred.reduce(0) { $0 + $1 * $1 }
            if energy > Float(size) * 0.25 {
                var best = (lag: 0, value: -Double.infinity)
                for lag in -reach...reach {
                    let from = start + lag
                    guard from >= 0, from + size <= rendered.count else { continue }
                    let other = rendered[from..<from + size]
                    let otherMean = other.reduce(0, +) / Float(size)
                    var product: Float = 0, otherEnergy: Float = 0
                    for (index, value) in other.enumerated() {
                        let centredOther = value - otherMean
                        product += centred[index] * centredOther
                        otherEnergy += centredOther * centredOther
                    }
                    let value = Double(product / max(1e-6, (energy * otherEnergy).squareRoot()))
                    if value > best.value { best = (lag, value) }
                }
                if best.value > -Double.infinity {
                    result.append(Window(
                        at: Double(start) / rate, lagMs: Double(best.lag) * 1_000 / rate,
                        correlation: (best.value * 1_000).rounded() / 1_000))
                }
            }
            start += size
        }
        return result
    }

    /// The windows and the straight-line drift through their lags (ms per minute), with the lag at the start and
    /// the end of that line.
    public static func json(_ windows: [Window], renderedSeconds: Double, timelineSeconds: Double) -> JSONValue {
        var result: [String: JSONValue] = [
            "windows": .array(windows.map { window in
                .object([
                    "at": .number(window.at), "lagMs": .number(window.lagMs), "correlation": .number(window.correlation),
                ])
            }),
            "renderedSeconds": .number((renderedSeconds * 1_000).rounded() / 1_000),
            "timelineSeconds": .number((timelineSeconds * 1_000).rounded() / 1_000),
        ]
        if windows.count >= 2 {
            let xs = windows.map(\.at), ys = windows.map(\.lagMs)
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            let slope = sxx > 0 ? zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx : 0
            result["driftMsPerMinute"] = .number((slope * 60 * 10).rounded() / 10)
            result["lagStartMs"] = .number((my + slope * ((xs.first ?? 0) - mx)).rounded())
            result["lagEndMs"] = .number((my + slope * ((xs.last ?? 0) - mx)).rounded())
        }
        return .object(result)
    }
}
