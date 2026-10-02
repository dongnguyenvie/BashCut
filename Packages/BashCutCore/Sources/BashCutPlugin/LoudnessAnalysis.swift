import BashCutProject
import Foundation

public struct LoudnessMeasurement: Sendable, Equatable {
    public let integratedLUFS: Double
    public let truePeakDbTP: Double
    public let loudnessRangeLU: Double?

    public init(integratedLUFS: Double, truePeakDbTP: Double, loudnessRangeLU: Double? = nil) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
    }

    public init(result: JSONValue) throws {
        let values = result.object
        guard let integrated = values["integratedLUFS"]?.double,
            let peak = values["truePeakDbTP"]?.double,
            integrated.isFinite, (-100...10).contains(integrated),
            peak.isFinite, (-100...20).contains(peak)
        else { throw PluginError.invalid("Loudness provider returned invalid LUFS or true peak") }
        let range = values["loudnessRangeLU"]?.double
        if let range, !range.isFinite || !(0...100).contains(range) {
            throw PluginError.invalid("Loudness range must be between 0 and 100 LU")
        }
        integratedLUFS = integrated
        truePeakDbTP = peak
        loudnessRangeLU = range
    }
}

public enum LoudnessNormalizer {
    public static func correction(
        measurement: LoudnessMeasurement, targetLUFS: Double = -14, peakCeilingDbTP: Double = -1
    ) throws -> Double {
        guard targetLUFS.isFinite, (-30 ... -5).contains(targetLUFS),
            peakCeilingDbTP.isFinite, (-12...0).contains(peakCeilingDbTP)
        else { throw PluginError.invalid("Invalid loudness normalization target") }
        let loudnessGain = targetLUFS - measurement.integratedLUFS
        let peakHeadroom = peakCeilingDbTP - measurement.truePeakDbTP
        return max(-60, min(24, min(loudnessGain, peakHeadroom)))
    }
}
