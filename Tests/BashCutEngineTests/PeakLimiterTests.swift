import Foundation
import Testing

@testable import BashCutEngine

/// The normalized export's look-ahead limiter.
struct PeakLimiterTests {
    /// Interleaved stereo: a 440 Hz tone at `quiet`, with bursts at `loud` every half second.
    func signal(seconds: Double, quiet: Float, loud: Float) -> [Float] {
        let rate = 48_000.0
        return (0..<Int(seconds * rate)).flatMap { index -> [Float] in
            let time = Double(index) / rate
            let level = time.truncatingRemainder(dividingBy: 0.5) < 0.05 ? loud : quiet
            let value = level * Float(sin(2 * .pi * 440 * time))
            return [value, -value]
        }
    }

    @Test("Peaks over the ceiling are held under it, across buffers, without touching quiet parts")
    func limits() {
        var samples = signal(seconds: 2, quiet: 0.2, loud: 1.6)
        var limiter = PeakLimiter(ceilingDb: -2, sampleRate: 48_000, channels: 2)
        let chunk = 1_024 * 2
        for start in stride(from: 0, to: samples.count, by: chunk) {
            samples[start..<min(start + chunk, samples.count)].withUnsafeMutableBufferPointer { limiter.process($0) }
        }
        let ceiling = Float(pow(10, -2.0 / 20))
        #expect(samples.map(abs).max()! <= ceiling + 1e-5)
        #expect(limiter.deepestReductionDb > 6 && limiter.deepestReductionDb < 7.5)
        // Well after a burst (released to within 1 %), a quiet stretch comes out as it went in, delayed by the look-ahead.
        let original = signal(seconds: 2, quiet: 0.2, loud: 1.6)
        let frame = Int(0.45 * 48_000), delay = limiter.lookahead
        #expect(abs(samples[frame * 2] - original[(frame - delay) * 2]) < 0.002)
    }

    @Test("A signal under the ceiling passes unchanged apart from the delay")
    func transparent() {
        var samples = signal(seconds: 0.5, quiet: 0.3, loud: 0.5)
        let original = samples
        var limiter = PeakLimiter(ceilingDb: -1, sampleRate: 48_000, channels: 2)
        samples.withUnsafeMutableBufferPointer { limiter.process($0) }
        let delay = limiter.lookahead * 2
        #expect(zip(samples[delay...], original).allSatisfy { abs($0 - $1) < 1e-6 })
        #expect(limiter.deepestReductionDb == 0)
    }
}
