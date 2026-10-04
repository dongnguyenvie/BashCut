import BashCutProject
import Foundation

public struct LoudnessMeasurement: Sendable, Equatable {
    public let integratedLUFS: Double
    public let truePeakDbTP: Double
    public let loudnessRangeLU: Double?
    /// Energy share in the speech band (300–3000 Hz), when the provider was asked for `bands`.
    public let speechShare: Double?
    /// Energy share in the presence band (1–4 kHz), when the provider was asked for `bands`.
    public let presenceShare: Double?

    public init(
        integratedLUFS: Double, truePeakDbTP: Double, loudnessRangeLU: Double? = nil, speechShare: Double? = nil,
        presenceShare: Double? = nil
    ) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
        self.speechShare = speechShare
        self.presenceShare = presenceShare
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
        let shares = ["speechShare", "presenceShare"].map { values[$0]?.double }
        if shares.contains(where: { $0.map { !$0.isFinite || !(0...1).contains($0) } ?? false }) {
            throw PluginError.invalid("Band shares must be between 0 and 1")
        }
        integratedLUFS = integrated
        truePeakDbTP = peak
        loudnessRangeLU = range
        speechShare = shares[0]
        presenceShare = shares[1]
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = ["integratedLUFS": .number(integratedLUFS), "truePeakDbTP": .number(truePeakDbTP)]
        if let loudnessRangeLU { fields["loudnessRangeLU"] = .number(loudnessRangeLU) }
        if let speechShare { fields["speechShare"] = .number(speechShare) }
        if let presenceShare { fields["presenceShare"] = .number(presenceShare) }
        return .object(fields)
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
