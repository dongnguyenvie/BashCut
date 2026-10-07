import Accelerate
import Foundation

/// How the music's energy moves (P0-B10 `audio.energy`): every 0.1 s its level (RMS dBFS), onset density (mean onset
/// strength, as the beat tracker hears it) and fullness (the share of eight octave bands from 63 Hz within 20 dB of
/// the strongest one), and the largest rises (lift), falls (drop) and dips (breath) of the level between two-second
/// windows, each snapped to the nearest beat. Candidates are pointers ranked by size, not cut decisions.
public enum EnergyCurve {
    public static let sampleRate = BeatTracker.sampleRate
    public static let step = 0.1

    public struct Candidate: Sendable, Equatable {
        public let kind: String
        public let seconds: Double
        /// dB of the change (lift and drop) or of the dip under its neighbours (breath).
        public let magnitude: Double
        public let beatSeconds: Double?
    }

    public struct Result: Sendable, Equatable {
        public let levelDb: [Double]
        public let onset: [Double]
        public let fullness: [Double]
        public let candidates: [Candidate]
    }

    /// `samples` are mono at 22.05 kHz; `beats` (seconds) snap the candidates; `count` of each kind are kept.
    public static func measure(_ samples: [Float], beats: [Double], count: Int = 6, window: Double = 2) -> Result {
        let blockSize = Int(sampleRate * step)
        let blocks = samples.count / max(1, blockSize)
        let level: [Double] = (0..<blocks).map { index in
            var square: Float = 0
            samples.withUnsafeBufferPointer { vDSP_measqv($0.baseAddress! + index * blockSize, 1, &square, vDSP_Length(blockSize)) }
            return square > 0 ? max(-100, 10 * log10(Double(square))) : -100
        }
        let envelope = BeatTracker.onsetEnvelope(samples)
        let perBlock = Double(blockSize) / Double(BeatTracker.hop)
        let onset: [Double] = (0..<blocks).map { index in
            let from = Int(Double(index) * perBlock), to = min(envelope.count, Int(Double(index + 1) * perBlock))
            guard to > from else { return 0 }
            return (Double(envelope[from..<to].reduce(0, +)) / Double(to - from) * 100).rounded() / 100
        }
        // Octave bands from 63 Hz: band b spans 63 × 2^b to 63 × 2^(b+1) Hz.
        let binHz = sampleRate / Double(BeatTracker.frameSize)
        var bandSums = [[Double]](repeating: [Double](repeating: 0, count: 8), count: blocks)
        BeatTracker.spectra(samples) { index, magnitude in
            let block = Int(Double(index * BeatTracker.hop) / Double(blockSize))
            guard block < blocks else { return }
            for band in 0..<8 {
                let low = Int(63 * pow(2, Double(band)) / binHz)
                let high = min(magnitude.count, Int(63 * pow(2, Double(band + 1)) / binHz))
                guard high > low else { continue }
                for bin in low..<high { bandSums[block][band] += Double(magnitude[bin] * magnitude[bin]) }
            }
        }
        let fullness: [Double] = bandSums.map { sums in
            let levels = sums.map { $0 > 0 ? 10 * log10($0) : -200 }
            guard let top = levels.max(), top > -200 else { return 0 }
            return Double(levels.filter { $0 >= top - 20 }.count) / 8
        }
        return Result(
            levelDb: level.map { ($0 * 10).rounded() / 10 }, onset: onset, fullness: fullness,
            candidates: candidates(level, beats: beats, count: count, window: window))
    }

    /// Mean level of `window` seconds before and after each block: the biggest rises and falls, and the blocks most
    /// below both neighbours, at least one window apart within a kind.
    static func candidates(_ level: [Double], beats: [Double], count: Int, window: Double) -> [Candidate] {
        let size = Int(window / step)
        guard level.count > size * 2 else { return [] }
        let mean = { (range: Range<Int>) in level[range].reduce(0, +) / Double(range.count) }
        var changes: [(index: Int, change: Double, dip: Double)] = []
        for index in size..<(level.count - size) {
            let before = mean((index - size)..<index), after = mean(index..<(index + size))
            let here = mean(max(0, index - 2)..<min(level.count, index + 3))
            changes.append((index, after - before, min(before, after) - here))
        }
        func pick(_ kind: String, _ score: ((index: Int, change: Double, dip: Double)) -> Double) -> [Candidate] {
            var chosen: [Candidate] = []
            for entry in changes.sorted(by: { score($0) > score($1) }) where score(entry) > 0 {
                let seconds = Double(entry.index) * step
                guard !chosen.contains(where: { abs($0.seconds - seconds) < window }) else { continue }
                let beat = beats.min { abs($0 - seconds) < abs($1 - seconds) }
                chosen.append(Candidate(
                    kind: kind, seconds: (seconds * 10).rounded() / 10, magnitude: (score(entry) * 10).rounded() / 10,
                    beatSeconds: beat))
                if chosen.count == count { break }
            }
            return chosen
        }
        return pick("lift") { $0.change } + pick("drop") { -$0.change } + pick("breath") { $0.dip }
    }
}
