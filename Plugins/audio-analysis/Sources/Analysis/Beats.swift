import Accelerate
import Foundation

/// Tempo and beat times of mono audio: a spectral-flux onset envelope, tempo from its autocorrelation (weighted
/// toward 120 BPM), then dynamic-programming beat tracking (Ellis 2007), all with vDSP.
public enum BeatTracker {
    public static let sampleRate = 22_050.0
    static let frameSize = 1024
    static let hop = 256
    static var envelopeRate: Double { sampleRate / Double(hop) }

    public struct Result: Sendable, Equatable {
        public let bpm: Double
        public let beatsSeconds: [Double]
    }

    /// `samples` are mono at 22.05 kHz.
    public static func track(_ samples: [Float], minimumBPM: Double = 60, maximumBPM: Double = 200) throws -> Result {
        let envelope = onsetEnvelope(samples)
        guard envelope.count > Int(envelopeRate * 2) else { throw AnalysisError("The audio is too short to find a tempo") }
        guard let period = tempoPeriod(envelope, minimumBPM: minimumBPM, maximumBPM: maximumBPM) else {
            throw AnalysisError("No beat found in the audio")
        }
        let frames = beatFrames(envelope, period: period)
        guard frames.count >= 2 else { throw AnalysisError("No beat found in the audio") }
        // A frame's onset is heard at the middle of its window.
        let times = frames.map { (Double($0 * hop) + Double(frameSize) / 2) / sampleRate }
        return Result(bpm: (keptTempo(times) * 10).rounded() / 10, beatsSeconds: times.map { ($0 * 1000).rounded() / 1000 })
    }

    /// The tempo the beats keep: a least-squares line through beat number and time, numbering beats by the median
    /// spacing so a skipped beat does not bend it. Frame times are quantized to the hop; the line averages that out.
    static func keptTempo(_ times: [Double]) -> Double {
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }.sorted()
        let median = gaps[gaps.count / 2]
        // Number each beat from the one before it, so the median's own quantization does not accumulate.
        var numbers: [Double] = [0]
        for (previous, time) in zip(times, times.dropFirst()) {
            numbers.append(numbers[numbers.count - 1] + max(1, ((time - previous) / median).rounded()))
        }
        let count = Double(times.count)
        let meanNumber = numbers.reduce(0, +) / count
        let meanTime = times.reduce(0, +) / count
        let covariance = zip(numbers, times).reduce(0) { $0 + ($1.0 - meanNumber) * ($1.1 - meanTime) }
        let variance = numbers.reduce(0) { $0 + ($1 - meanNumber) * ($1 - meanNumber) }
        let period = variance > 0 ? covariance / variance : median
        return 60 / (period > 0 ? period : median)
    }

    // MARK: Onsets

    /// Positive change of log-compressed magnitude spectra between frames, minus a local mean, one value per hop.
    static func onsetEnvelope(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameSize else { return [] }
        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        let bins = frameSize / 2
        var previous = [Float](repeating: 0, count: bins)
        var flux: [Float] = []
        var frame = [Float](repeating: 0, count: frameSize)
        var real = [Float](repeating: 0, count: bins)
        var imaginary = [Float](repeating: 0, count: bins)
        var magnitude = [Float](repeating: 0, count: bins)
        var start = 0
        while start + frameSize <= samples.count {
            samples.withUnsafeBufferPointer { buffer in
                vDSP_vmul(buffer.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(frameSize))
            }
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                    frame.withUnsafeBufferPointer { framePointer in
                        framePointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: bins) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(bins))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(bins))
                }
            }
            // log(1 + γ|X|) compresses dynamics so quiet onsets count too.
            var value: Float = 0
            for bin in 1..<bins {
                let current = log1p(100 * magnitude[bin])
                value += max(0, current - previous[bin])
                previous[bin] = current
            }
            flux.append(start == 0 ? 0 : value)
            start += hop
        }
        // Subtract a ~0.5 s moving average and keep the positive part.
        let radius = Int(envelopeRate * 0.25)
        var smoothed = [Float](repeating: 0, count: flux.count)
        var running: Float = 0
        var count = 0
        var low = 0
        var high = -1
        for index in flux.indices {
            while high < min(flux.count - 1, index + radius) { high += 1; running += flux[high]; count += 1 }
            while low < index - radius { running -= flux[low]; low += 1; count -= 1 }
            smoothed[index] = max(0, flux[index] - running / Float(max(count, 1)))
        }
        var deviation: Float = 0
        var mean: Float = 0
        vDSP_normalize(smoothed, 1, nil, 1, &mean, &deviation, vDSP_Length(smoothed.count))
        guard deviation > 0 else { return smoothed }
        return smoothed.map { $0 / deviation }
    }

    // MARK: Tempo

    /// Beat period in envelope frames: the autocorrelation lag with the most energy, weighted by a log-normal
    /// prior around 120 BPM so half and double tempos lose ties.
    static func tempoPeriod(_ envelope: [Float], minimumBPM: Double, maximumBPM: Double) -> Double? {
        let minimumLag = Int((60 / maximumBPM * envelopeRate).rounded(.down))
        let maximumLag = Int((60 / minimumBPM * envelopeRate).rounded(.up))
        guard envelope.count > maximumLag + 1, minimumLag >= 1 else { return nil }
        var correlation = [Float](repeating: 0, count: maximumLag + 2)
        let length = envelope.count - maximumLag - 1
        envelope.withUnsafeBufferPointer { buffer in
            for lag in 0...(maximumLag + 1) {
                var value: Float = 0
                vDSP_dotpr(buffer.baseAddress!, 1, buffer.baseAddress! + lag, 1, &value, vDSP_Length(length))
                correlation[lag] = value
            }
        }
        guard correlation[0] > 0 else { return nil }
        var best = -1
        var bestScore = -Double.infinity
        for lag in minimumLag...maximumLag {
            let bpm = 60 * envelopeRate / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 120), 2))
            let score = Double(correlation[lag]) * prior
            if score > bestScore { bestScore = score; best = lag }
        }
        guard best > 0, bestScore > 0 else { return nil }
        // Parabolic interpolation around the peak for a fractional period.
        let left = Double(correlation[best - 1]), center = Double(correlation[best]), right = Double(correlation[best + 1])
        let denominator = left - 2 * center + right
        let shift = denominator == 0 ? 0 : max(-0.5, min(0.5, 0.5 * (left - right) / denominator))
        return Double(best) + shift
    }

    // MARK: Beat tracking

    /// Frames of the beat sequence that maximizes onset strength while keeping spacing close to `period`.
    static func beatFrames(_ envelope: [Float], period: Double, tightness: Double = 100) -> [Int] {
        let count = envelope.count
        var score = [Double](repeating: 0, count: count)
        var backlink = [Int](repeating: -1, count: count)
        let lowest = Int((period / 2).rounded())
        let highest = Int((period * 2).rounded())
        for frame in 0..<count {
            var best = 0.0
            var link = -1
            if frame >= lowest {
                for previous in max(0, frame - highest)...(frame - lowest) {
                    let gap = Double(frame - previous)
                    let penalty = -tightness * pow(log(gap / period), 2)
                    let candidate = score[previous] + penalty
                    if link < 0 || candidate > best { best = candidate; link = previous }
                }
            }
            // Starting a new sequence here costs nothing, so the first onset is never traded for a better gap.
            if link >= 0, best < 0 { link = -1 }
            score[frame] = Double(envelope[frame]) + (link >= 0 ? best : 0)
            backlink[frame] = link
        }
        // End on the best-scoring frame in the last beat period, then walk back.
        let tailStart = max(0, count - Int(period.rounded()) - 1)
        guard var frame = (tailStart..<count).max(by: { score[$0] < score[$1] }) else { return [] }
        var frames: [Int] = []
        while frame >= 0 {
            frames.append(frame)
            frame = backlink[frame]
        }
        // Drop leading beats before the first real onset (silence at the start).
        let reversed = Array(frames.reversed())
        let threshold: Float = 0.1
        guard let firstStrong = reversed.firstIndex(where: { envelope[$0] > threshold }) else { return reversed }
        return Array(reversed[firstStrong...])
    }
}
