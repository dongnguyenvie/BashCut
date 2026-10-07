import Foundation

/// A reference and our render measured by the same functions (P1-E8, `review.compare`): raw values side by side with
/// the difference (ours − reference). No verdict: a metric gets `within` only when the project's `review.compare`
/// gives its tolerance.
public enum ReviewCompare {
    /// Metric → value for one measured file.
    public static func metrics(_ analysis: MediaAnalysis, minScore: Double = MediaAnalysis.Limits().minScore) -> [String: Double] {
        var values: [String: Double] = ["durationSeconds": analysis.tech.seconds]
        if let picture = analysis.picture, picture.fps > 0 {
            let frames = [0] + analysis.cuts(minScore: minScore).map(\.frame) + [picture.frames]
            let lengths = zip(frames, frames.dropFirst()).map { Double($1 - $0) / picture.fps }.filter { $0 > 0 }
            values["shots"] = Double(lengths.count)
            values["shotSecondsMedian"] = percentile(lengths, 0.5)
            values["shotSecondsP25"] = percentile(lengths, 0.25)
            values["shotSecondsP75"] = percentile(lengths, 0.75)
            let minutes = Double(picture.frames) / picture.fps / 60
            if minutes > 0 { values["cutsPerMinute"] = Double(max(0, lengths.count - 1)) / minutes }
            for (name, read) in [
                ("luma", \MediaAnalysis.Sample.luma), ("spread", \.spread), ("change", \.change),
                ("colourfulness", \.colourfulness), ("sharpness", \.sharpness),
            ] as [(String, KeyPath<MediaAnalysis.Sample, Double>)] {
                values[name + "Median"] = percentile(picture.samples.map { $0[keyPath: read] }, 0.5)
            }
        }
        if let sound = analysis.sound, !sound.levels.isEmpty {
            values["levelMedianDb"] = percentile(sound.levels, 0.5)
            values["levelP10Db"] = percentile(sound.levels, 0.1)
            values["levelP90Db"] = percentile(sound.levels, 0.9)
            values["levelRangeDb"] = (percentile(sound.levels, 0.9) ?? 0) - (percentile(sound.levels, 0.1) ?? 0)
            values["peakDb"] = sound.peakDb
        }
        return values.compactMapValues { $0 }
    }

    static func percentile(_ values: [Double], _ share: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * share).rounded()))]
    }

    public static func json(reference: MediaAnalysis, ours: MediaAnalysis, tolerances: [String: Double]) -> JSONValue {
        let left = metrics(reference), right = metrics(ours)
        let round = { (value: Double) in JSONValue.number((value * 1_000).rounded() / 1_000) }
        let rows: [JSONValue] = Set(left.keys).union(right.keys).sorted().map { metric in
            var row: [String: JSONValue] = [
                "metric": .string(metric), "reference": left[metric].map(round) ?? .null, "ours": right[metric].map(round) ?? .null,
            ]
            if let a = left[metric], let b = right[metric] {
                row["delta"] = round(b - a)
                if let tolerance = tolerances[metric] {
                    row["tolerance"] = round(tolerance)
                    row["within"] = .bool(abs(b - a) <= tolerance)
                }
            }
            return .object(row)
        }
        return .object(["rows": .array(rows), "tolerancesFrom": .string("review.compare")])
    }
}
