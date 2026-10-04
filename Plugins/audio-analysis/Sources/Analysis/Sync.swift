import Accelerate
import Foundation

/// Time offset between two recordings of the same moment (a camera and a screen recording, or a render played back
/// inside a screen recording), from their sound. Both loudness envelopes (100 per second, log RMS) are
/// cross-correlated: a coarse search at 10 per second over every overlap of at least half the shorter file, then a
/// fine one at 100 per second around the best lag. Each half of the overlap is matched again; two agreeing offsets
/// mean a constant offset (no clock drift).
public enum AudioSync {
    public static let sampleRate = 8_000.0
    static let envelopeRate = 100
    /// Fine search radius around the coarse lag, in envelope values (±0.3 s).
    static let fineRadius = 30

    public struct Match: Sendable, Equatable {
        /// Time in the second file = time in the first + `offsetSeconds`.
        public let offsetSeconds: Double
        /// Normalized correlation of the envelopes, −1 to 1.
        public let correlation: Double
    }

    public struct Result: Sendable, Equatable {
        public let match: Match
        /// The overlap in the first file's time.
        public let overlapStartSeconds: Double
        public let overlapEndSeconds: Double
        /// The match of each half of the overlap.
        public let halves: [Match]

        /// The halves agree within 0.02 s.
        public var isSteady: Bool {
            halves.count == 2 && abs(halves[0].offsetSeconds - halves[1].offsetSeconds) <= 0.02 + 1e-9
        }
    }

    /// `first` and `second` are mono at 8 kHz.
    public static func align(_ first: [Float], _ second: [Float]) throws -> Result {
        let a = envelope(first), b = envelope(second)
        guard min(a.count, b.count) >= 3 * envelopeRate else {
            throw AnalysisError("Both files need at least 3 seconds of sound")
        }
        let minimumOverlap = min(a.count, b.count) / 2
        let coarseA = Envelope(decimate(a, 10)), coarseB = Envelope(decimate(b, 10))
        guard let coarse = best(coarseA, coarseB, lags: -(coarseA.count - 1)..<coarseB.count,
                                minimumOverlap: minimumOverlap / 10)
        else { throw AnalysisError("The files do not overlap enough to compare") }
        let fineA = Envelope(a), fineB = Envelope(b)
        let around = (coarse.lag * 10 - fineRadius)...(coarse.lag * 10 + fineRadius)
        guard let fine = best(fineA, fineB, lags: around, minimumOverlap: minimumOverlap) else {
            throw AnalysisError("The files do not overlap enough to compare")
        }
        let start = max(0, -fine.lag), end = min(a.count, b.count - fine.lag)
        let middle = (start + end) / 2
        let lags = (fine.lag - fineRadius)...(fine.lag + fineRadius)
        let halves = [(start, middle), (middle, end)].compactMap { range in
            best(fineA, fineB, lags: lags, minimumOverlap: (middle - start) / 2, within: range.0..<range.1)
                .map { Match(offsetSeconds: Double($0.lag) / Double(envelopeRate), correlation: rounded($0.correlation)) }
        }
        return Result(
            match: Match(offsetSeconds: Double(fine.lag) / Double(envelopeRate), correlation: rounded(fine.correlation)),
            overlapStartSeconds: Double(start) / Double(envelopeRate), overlapEndSeconds: Double(end) / Double(envelopeRate),
            halves: halves)
    }

    static func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    /// Log RMS of 10 ms windows.
    static func envelope(_ samples: [Float]) -> [Double] {
        let hop = Int(sampleRate) / envelopeRate
        guard samples.count >= hop else { return [] }
        return samples.withUnsafeBufferPointer { buffer in
            (0..<(samples.count / hop)).map { index in
                var square: Float = 0
                vDSP_measqv(buffer.baseAddress! + index * hop, 1, &square, vDSP_Length(hop))
                // Samples are ±1 floats; scale to 16-bit units so quiet rooms keep their shape above the +1 floor.
                return log(Double(square).squareRoot() * 32_768 + 1)
            }
        }
    }

    static func decimate(_ values: [Double], _ factor: Int) -> [Double] {
        stride(from: 0, through: values.count - factor, by: factor).map { start in
            values[start..<start + factor].reduce(0, +) / Double(factor)
        }
    }

    /// Values with prefix sums, so each lag's means and variances are O(1) and only the product needs a pass.
    struct Envelope {
        let values: [Double]
        let sums: [Double]
        let squares: [Double]
        var count: Int { values.count }

        init(_ values: [Double]) {
            self.values = values
            var sums = [0.0], squares = [0.0]
            sums.reserveCapacity(values.count + 1)
            squares.reserveCapacity(values.count + 1)
            for value in values {
                sums.append(sums[sums.count - 1] + value)
                squares.append(squares[squares.count - 1] + value * value)
            }
            self.sums = sums
            self.squares = squares
        }

        func sum(_ range: Range<Int>) -> Double { sums[range.upperBound] - sums[range.lowerBound] }
        func squareSum(_ range: Range<Int>) -> Double { squares[range.upperBound] - squares[range.lowerBound] }
    }

    /// Normalized correlation of a[t] with b[t + lag] over their overlap, restricted to a's `within`.
    static func correlation(_ a: Envelope, _ b: Envelope, lag: Int, within: Range<Int>? = nil) -> (Double, Int) {
        let limit = within ?? 0..<a.count
        let start = max(limit.lowerBound, -lag), end = min(limit.upperBound, b.count - lag)
        let count = end - start
        guard count >= 20 else { return (-1, max(0, count)) }
        var product = 0.0
        a.values.withUnsafeBufferPointer { left in
            b.values.withUnsafeBufferPointer { right in
                vDSP_dotprD(left.baseAddress! + start, 1, right.baseAddress! + start + lag, 1, &product, vDSP_Length(count))
            }
        }
        let n = Double(count)
        let sumA = a.sum(start..<end), sumB = b.sum((start + lag)..<(end + lag))
        let varianceA = n * a.squareSum(start..<end) - sumA * sumA
        let varianceB = n * b.squareSum((start + lag)..<(end + lag)) - sumB * sumB
        guard varianceA > 1e-9, varianceB > 1e-9 else { return (-1, count) }
        return ((n * product - sumA * sumB) / (varianceA * varianceB).squareRoot(), count)
    }

    static func best<Lags: Sequence<Int>>(
        _ a: Envelope, _ b: Envelope, lags: Lags, minimumOverlap: Int, within: Range<Int>? = nil
    ) -> (lag: Int, correlation: Double)? {
        var top: (lag: Int, correlation: Double)?
        for lag in lags {
            let (value, count) = correlation(a, b, lag: lag, within: within)
            if count >= max(20, minimumOverlap), value > (top?.correlation ?? -2) { top = (lag, value) }
        }
        return top
    }
}
