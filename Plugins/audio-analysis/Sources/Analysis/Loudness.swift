import Accelerate
import Foundation

/// Integrated loudness, loudness range and true peak of 48 kHz audio, following ITU-R BS.1770-4 (K-weighting,
/// 400 ms blocks with 75 % overlap, absolute gate −70 LUFS, relative gate −10 LU) and EBU Tech 3342 (3 s windows,
/// relative gate −20 LU, 10th to 95th percentile). True peak uses 4× oversampling with a windowed-sinc filter.
public enum LoudnessMeter {
    public static let sampleRate = 48_000.0

    public struct Result: Sendable, Equatable {
        public let integratedLUFS: Double
        public let truePeakDbTP: Double
        public let loudnessRangeLU: Double?
    }

    /// `channels` are deinterleaved channels of equal length at 48 kHz (1 or 2; surround should be downmixed).
    /// Silent audio throws unless `allowSilence`, which reports −100 LUFS instead.
    public static func measure(_ channels: [[Float]], allowSilence: Bool = false) throws -> Result {
        guard let length = channels.first?.count, length > 0, channels.allSatisfy({ $0.count == length }) else {
            throw AnalysisError("The audio is empty")
        }
        let weighted = channels.map(kWeight)
        let block = Int(sampleRate * 0.4)
        let step = Int(sampleRate * 0.1)
        let blocks = meanSquares(weighted, window: block, step: step)
        guard let integrated = gatedLoudness(blocks, relativeGate: -10) ?? (allowSilence ? -100 : nil) else {
            throw AnalysisError("The audio is silent")
        }
        let shortTerm = meanSquares(weighted, window: Int(sampleRate * 3), step: step)
        return Result(
            integratedLUFS: max(-100, integrated), truePeakDbTP: truePeak(channels),
            loudnessRangeLU: loudnessRange(shortTerm))
    }

    /// Loudness over time, every 100 ms from the start: momentary (400 ms windows) and short-term (3 s windows)
    /// loudness in LUFS (−100 for silence), and the sample peak of each 100 ms in dBFS. Window `i` starts at
    /// `i × 0.1` s; the last windows are left out where they would run past the end.
    public static func curve(_ channels: [[Float]]) -> (momentary: [Double], shortTerm: [Double], peakDb: [Double]) {
        guard let length = channels.first?.count, length > 0 else { return ([], [], []) }
        let weighted = channels.map(kWeight)
        let step = Int(sampleRate * 0.1)
        let level = { (value: Double) in value > 1e-10 ? max(-100, loudness(value)) : -100 }
        let momentary = meanSquares(weighted, window: Int(sampleRate * 0.4), step: step).map(level)
        let shortTerm = length >= Int(sampleRate * 3)
            ? meanSquares(weighted, window: Int(sampleRate * 3), step: step).map(level) : []
        var peaks: [Double] = []
        var start = 0
        while start < length {
            let end = min(length, start + step)
            var peak: Float = 0
            for channel in channels {
                var value: Float = 0
                channel.withUnsafeBufferPointer { buffer in
                    vDSP_maxmgv(buffer.baseAddress! + start, 1, &value, vDSP_Length(end - start))
                }
                peak = max(peak, value)
            }
            peaks.append(peak > 0 ? max(-100, 20 * log10(Double(peak))) : -100)
            start = end
        }
        return (momentary, shortTerm, peaks)
    }

    // MARK: K-weighting

    /// Two biquads at 48 kHz: the head-related high shelf, then the RLB high-pass.
    static func kWeight(_ samples: [Float]) -> [Float] {
        let shelf = biquad(
            samples, b: [1.53512485958697, -2.69169618940638, 1.19839281085285], a: [-1.69065929318241, 0.73248077421585])
        return biquad(shelf, b: [1, -2, 1], a: [-1.99004745483398, 0.99007225036621])
    }

    /// Direct form I biquad; `a` holds a1 and a2 (a0 = 1). vDSP_deq22 wants b0, b1, b2, a1, a2 and two primed
    /// samples on each side.
    static func biquad(_ samples: [Float], b: [Double], a: [Double]) -> [Float] {
        let input = [Float](repeating: 0, count: 2) + samples
        var output = [Float](repeating: 0, count: input.count)
        let coefficients = (b + a).map { Float($0) }
        vDSP_deq22(input, 1, coefficients, &output, 1, vDSP_Length(samples.count))
        return Array(output.dropFirst(2))
    }

    // MARK: Gating

    /// Sum over channels of each window's mean square (all channel weights are 1 for mono and stereo).
    static func meanSquares(_ channels: [[Float]], window: Int, step: Int) -> [Double] {
        guard let length = channels.first?.count else { return [] }
        // A file shorter than one window is measured as one window.
        let window = min(window, length)
        var values: [Double] = []
        var start = 0
        while start + window <= length {
            var total = 0.0
            for channel in channels {
                var square: Float = 0
                channel.withUnsafeBufferPointer { buffer in
                    vDSP_measqv(buffer.baseAddress! + start, 1, &square, vDSP_Length(window))
                }
                total += Double(square)
            }
            values.append(total)
            start += step
        }
        return values
    }

    static func loudness(_ meanSquare: Double) -> Double { -0.691 + 10 * log10(max(meanSquare, 1e-12)) }

    /// Power mean of the blocks above −70 LUFS and above (their mean − `relativeGate`), in LUFS.
    static func gatedLoudness(_ blocks: [Double], relativeGate: Double) -> Double? {
        let absolute = blocks.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let threshold = loudness(absolute.reduce(0, +) / Double(absolute.count)) + relativeGate
        let relative = absolute.filter { loudness($0) > threshold }
        guard !relative.isEmpty else { return nil }
        return loudness(relative.reduce(0, +) / Double(relative.count))
    }

    /// EBU Tech 3342: spread between the 10th and 95th percentile of gated short-term loudness.
    static func loudnessRange(_ shortTerm: [Double]) -> Double? {
        let absolute = shortTerm.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let threshold = loudness(absolute.reduce(0, +) / Double(absolute.count)) - 20
        let values = absolute.map(loudness).filter { $0 > threshold }.sorted()
        guard values.count > 1 else { return 0 }
        func percentile(_ fraction: Double) -> Double {
            values[min(values.count - 1, Int((Double(values.count - 1) * fraction).rounded()))]
        }
        return min(100, max(0, percentile(0.95) - percentile(0.10)))
    }

    // MARK: True peak

    static let oversampling = 4
    static let tapsPerPhase = 12

    /// Windowed-sinc interpolation filters, one per fractional phase 1/4, 2/4, 3/4.
    static let phaseFilters: [[Float]] = (1..<oversampling).map { phase in
        let half = Double(tapsPerPhase) / 2
        let offset = Double(phase) / Double(oversampling)
        return (0..<tapsPerPhase).map { tap in
            let x = Double(tap) - half + 1 - offset
            let sinc = x == 0 ? 1 : sin(.pi * x) / (.pi * x)
            let position = (Double(tap) + 1 - offset) / Double(tapsPerPhase)
            let window = 0.5 - 0.5 * cos(2 * .pi * position)
            return Float(sinc * window)
        }
    }

    /// Highest absolute sample of the signal and its 4× interpolation, in dBTP.
    static func truePeak(_ channels: [[Float]]) -> Double {
        var peak: Float = 0
        for channel in channels {
            var sampleMax: Float = 0
            vDSP_maxmgv(channel, 1, &sampleMax, vDSP_Length(channel.count))
            peak = max(peak, sampleMax)
            guard channel.count >= tapsPerPhase else { continue }
            let padded = [Float](repeating: 0, count: tapsPerPhase) + channel + [Float](repeating: 0, count: tapsPerPhase)
            let outputCount = padded.count - tapsPerPhase + 1
            var interpolated = [Float](repeating: 0, count: outputCount)
            for filter in phaseFilters {
                // vDSP_conv correlates; reversing the taps makes it a convolution.
                vDSP_conv(padded, 1, Array(filter.reversed()), 1, &interpolated, 1, vDSP_Length(outputCount),
                          vDSP_Length(tapsPerPhase))
                var phaseMax: Float = 0
                vDSP_maxmgv(interpolated, 1, &phaseMax, vDSP_Length(outputCount))
                peak = max(peak, phaseMax)
            }
        }
        return max(-100, 20 * log10(Double(max(peak, 1e-6))))
    }
}

public struct AnalysisError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
