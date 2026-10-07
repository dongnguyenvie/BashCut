import BashCutProject
import Foundation

/// Loudness over time from an `audio.loudness` provider asked for `curve` (#471): every `step` seconds from the
/// start, momentary (400 ms) and short-term (3 s) loudness in LUFS (−100 for silence) and the sample peak in dBFS.
public struct LoudnessCurve: Sendable, Equatable {
    public let step: Double
    public let momentary: [Double]
    public let shortTerm: [Double]
    public let peakDb: [Double]

    public init(step: Double = 0.1, momentary: [Double], shortTerm: [Double] = [], peakDb: [Double] = []) {
        self.step = step
        self.momentary = momentary
        self.shortTerm = shortTerm
        self.peakDb = peakDb
    }

    init(json value: JSONValue) throws {
        let fields = value.object
        let list = { (key: String) throws -> [Double] in
            let values = fields[key]?.array.compactMap(\.double) ?? []
            guard values.count == (fields[key]?.array.count ?? 0), values.count <= 1_000_000,
                values.allSatisfy({ $0.isFinite && (-200...30).contains($0) })
            else { throw PluginError.invalid("Loudness curve \(key) must hold finite levels") }
            return values
        }
        guard let step = fields["step"]?.double, step > 0, step <= 10 else {
            throw PluginError.invalid("Loudness curve step must be 0–10 s")
        }
        self.init(step: step, momentary: try list("momentary"), shortTerm: try list("shortTerm"), peakDb: try list("peakDb"))
    }

    public var json: JSONValue {
        .object([
            "step": .number(step), "momentary": .array(momentary.map(JSONValue.number)),
            "shortTerm": .array(shortTerm.map(JSONValue.number)), "peakDb": .array(peakDb.map(JSONValue.number)),
        ])
    }
}

public struct LoudnessMeasurement: Sendable, Equatable {
    public let integratedLUFS: Double
    public let truePeakDbTP: Double
    public let loudnessRangeLU: Double?
    /// Energy share in the speech band (300–3000 Hz), when the provider was asked for `bands`.
    public let speechShare: Double?
    /// Energy share in the presence band (1–4 kHz), when the provider was asked for `bands`.
    public let presenceShare: Double?
    /// Loudness over time, when the provider was asked for `curve`.
    public let curve: LoudnessCurve?

    public init(
        integratedLUFS: Double, truePeakDbTP: Double, loudnessRangeLU: Double? = nil, speechShare: Double? = nil,
        presenceShare: Double? = nil, curve: LoudnessCurve? = nil
    ) {
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
        self.speechShare = speechShare
        self.presenceShare = presenceShare
        self.curve = curve
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
        curve = try values["curve"].flatMap { $0 == .null ? nil : try LoudnessCurve(json: $0) }
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = ["integratedLUFS": .number(integratedLUFS), "truePeakDbTP": .number(truePeakDbTP)]
        if let loudnessRangeLU { fields["loudnessRangeLU"] = .number(loudnessRangeLU) }
        if let speechShare { fields["speechShare"] = .number(speechShare) }
        if let presenceShare { fields["presenceShare"] = .number(presenceShare) }
        if let curve { fields["curve"] = curve.json }
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
