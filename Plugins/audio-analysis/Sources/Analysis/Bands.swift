import Accelerate
import Foundation

/// How much of a file's sound sits where speech is understood: the energy share in the speech band (300–3000 Hz) and
/// in the presence band (1–4 kHz, where consonants carry the words). Music with a low presence share masks a voice
/// less. Each band is two 2nd-order Butterworth high-passes and two low-passes (24 dB/octave edges).
public enum SpectralShare {
    public static let sampleRate = LoudnessMeter.sampleRate

    public struct Result: Sendable, Equatable {
        public let speech: Double
        public let presence: Double
    }

    /// `channels` are deinterleaved at 48 kHz; they are mixed to mono.
    public static func measure(_ channels: [[Float]]) throws -> Result {
        guard let length = channels.first?.count, length > 0 else { throw AnalysisError("The audio is empty") }
        var mono = [Float](repeating: 0, count: length)
        for channel in channels { vDSP_vadd(mono, 1, channel, 1, &mono, 1, vDSP_Length(length)) }
        var scale = 1 / Float(channels.count)
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(length))
        let full = meanSquare(mono)
        guard full > 1e-12 else { throw AnalysisError("The audio is silent") }
        func share(_ low: Double, _ high: Double) -> Double {
            var band = mono
            for _ in 0..<2 { band = LoudnessMeter.biquad(band, coefficients: highPass(low)) }
            for _ in 0..<2 { band = LoudnessMeter.biquad(band, coefficients: lowPass(high)) }
            return min(1, (meanSquare(band) / full * 1000).rounded() / 1000)
        }
        return Result(speech: share(300, 3000), presence: share(1000, 4000))
    }

    static func meanSquare(_ samples: [Float]) -> Double {
        var value: Float = 0
        vDSP_measqv(samples, 1, &value, vDSP_Length(samples.count))
        return Double(value)
    }

    /// RBJ cookbook biquads with Q = 1/√2: b0, b1, b2 and a1, a2 normalized by a0.
    static func highPass(_ frequency: Double) -> (b: [Double], a: [Double]) {
        let (cosine, alpha) = shape(frequency)
        return normalized(b: [(1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2], a: [1 + alpha, -2 * cosine, 1 - alpha])
    }

    static func lowPass(_ frequency: Double) -> (b: [Double], a: [Double]) {
        let (cosine, alpha) = shape(frequency)
        return normalized(b: [(1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2], a: [1 + alpha, -2 * cosine, 1 - alpha])
    }

    private static func shape(_ frequency: Double) -> (Double, Double) {
        let omega = 2 * Double.pi * frequency / sampleRate
        return (cos(omega), sin(omega) / (2 * (0.5).squareRoot()))
    }

    private static func normalized(b: [Double], a: [Double]) -> (b: [Double], a: [Double]) {
        (b.map { $0 / a[0] }, [a[1] / a[0], a[2] / a[0]])
    }
}

extension LoudnessMeter {
    static func biquad(_ samples: [Float], coefficients: (b: [Double], a: [Double])) -> [Float] {
        biquad(samples, b: coefficients.b, a: coefficients.a)
    }
}
