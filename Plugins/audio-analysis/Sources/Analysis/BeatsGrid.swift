import Foundation

/// Beat grid v2 (P0-B10, PL2): how strong each beat is, which beats start a bar (the phase where the kick band hits
/// hardest), how well a straight grid fits the beats, how clearly the tempo stands out and how the half and double
/// tempos compare. Facts for the caller to weigh, not a verdict on whether the grid is good.
extension BeatTracker {
    public struct Grid: Sendable, Equatable {
        /// Onset strength at each beat, 0–1 of the strongest.
        public let strengths: [Double]
        /// Beat times that start a bar, assuming `beatsPerBar`.
        public let downbeats: [Double]
        /// Kick-band onset strength summed per phase of the bar, 0–1 of the strongest phase.
        public let phaseScores: [Double]
        public let beatsPerBar: Int
        /// Least-squares line through beat number and time: its period and phase (time of beat 0), and the RMS
        /// distance of the beats from it.
        public let periodSeconds: Double
        public let phaseSeconds: Double
        public let rmsErrorMs: Double
        /// Autocorrelation at the beat period over the zero-lag value (0–1): how much the tempo stands out.
        public let tempoStrength: Double
        /// Half and double tempo, each with its autocorrelation relative to the chosen tempo.
        public let alternates: [(bpm: Double, relative: Double)]

        public static func == (lhs: Grid, rhs: Grid) -> Bool {
            lhs.strengths == rhs.strengths && lhs.downbeats == rhs.downbeats && lhs.periodSeconds == rhs.periodSeconds
        }
    }

    /// The beats and their grid facts.
    public static func trackGrid(
        _ samples: [Float], beatsPerBar: Int = 4, minimumBPM: Double = 60, maximumBPM: Double = 200
    ) throws -> (Result, Grid) {
        let result = try track(samples, minimumBPM: minimumBPM, maximumBPM: maximumBPM)
        let envelope = onsetEnvelope(samples)
        let frameOf = { (seconds: Double) in
            min(envelope.count - 1, max(0, Int(((seconds * sampleRate) - Double(frameSize) / 2) / Double(hop))))
        }
        let peak = Double(envelope.max() ?? 1)
        let strengths = result.beatsSeconds.map { peak > 0 ? (Double(envelope[frameOf($0)]) / peak * 1_000).rounded() / 1_000 : 0 }
        // Kick band: up to about 150 Hz at 22.05 kHz with 1024-point frames.
        let kick = onsetEnvelope(samples, bins: 1..<8)
        let bars = max(1, beatsPerBar)
        var phases = [Double](repeating: 0, count: bars)
        for (index, seconds) in result.beatsSeconds.enumerated() where !kick.isEmpty {
            phases[index % bars] += Double(kick[min(kick.count - 1, frameOf(seconds))])
        }
        let best = phases.enumerated().max { $0.element < $1.element }?.offset ?? 0
        let strongest = phases.max() ?? 0
        let downbeats = result.beatsSeconds.enumerated().filter { $0.offset % bars == best }.map(\.element)
        let line = fit(result.beatsSeconds)
        let period = 60 / result.bpm * envelopeRate
        let maximumLag = Int((period * 2).rounded(.up)) + 2
        let correlation = autocorrelation(envelope, maximumLag: maximumLag)
        let at = { (lag: Double) -> Double in
            let index = Int(lag.rounded())
            return correlation.indices.contains(index) ? Double(correlation[index]) : 0
        }
        let chosen = at(period)
        let relative = { (lag: Double) in chosen > 0 ? (at(lag) / chosen * 1_000).rounded() / 1_000 : 0 }
        let grid = Grid(
            strengths: strengths, downbeats: downbeats,
            phaseScores: phases.map { strongest > 0 ? ($0 / strongest * 1_000).rounded() / 1_000 : 0 }, beatsPerBar: bars,
            periodSeconds: (line.period * 10_000).rounded() / 10_000, phaseSeconds: (line.phase * 1_000).rounded() / 1_000,
            rmsErrorMs: (line.rms * 1_000 * 10).rounded() / 10,
            tempoStrength: correlation[0] > 0 ? (chosen / Double(correlation[0]) * 1_000).rounded() / 1_000 : 0,
            alternates: [(result.bpm / 2, relative(period * 2)), (result.bpm * 2, relative(period / 2))])
        return (result, grid)
    }

    /// Least-squares line time = phase + period × number, numbering beats by the median gap.
    static func fit(_ times: [Double]) -> (period: Double, phase: Double, rms: Double) {
        guard times.count >= 2 else { return (0, times.first ?? 0, 0) }
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }.sorted()
        let median = gaps[gaps.count / 2]
        var numbers: [Double] = [0]
        for (previous, time) in zip(times, times.dropFirst()) {
            numbers.append(numbers[numbers.count - 1] + max(1, ((time - previous) / median).rounded()))
        }
        let count = Double(times.count)
        let meanNumber = numbers.reduce(0, +) / count, meanTime = times.reduce(0, +) / count
        let variance = numbers.reduce(0) { $0 + ($1 - meanNumber) * ($1 - meanNumber) }
        let period = variance > 0
            ? zip(numbers, times).reduce(0) { $0 + ($1.0 - meanNumber) * ($1.1 - meanTime) } / variance : median
        let phase = meanTime - period * meanNumber
        let rms = (zip(numbers, times).reduce(0) { total, pair in
            let error = pair.1 - (phase + period * pair.0)
            return total + error * error
        } / count).squareRoot()
        return (period, phase, rms)
    }
}
