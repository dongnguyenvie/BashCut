import BashCutEngine
import BashCutPlugin
import BashCutProject
import BashCutStorage
import Foundation

/// What an export produced, with its metrics compared against the previous export of the project.
public struct ExportReport: Sendable {
    public let receipt: ExportReceipt
    public let preset: ExportPreset
    public let cutCount: Int
    public let captionCount: Int
    public let includedSubRip: Bool
    public let loudness: LoudnessMeasurement?
    public let loudnessVerified: Bool
    public let appliedGainDb: Double?
    public let speechCoverage: Double
    public let completedAt: Date
    public let comparison: ExportMetricDelta?

    public init(
        receipt: ExportReceipt, preset: ExportPreset, cutCount: Int, captionCount: Int,
        includedSubRip: Bool, loudness: LoudnessMeasurement?, loudnessVerified: Bool,
        appliedGainDb: Double?, speechCoverage: Double, completedAt: Date,
        comparison: ExportMetricDelta?
    ) {
        self.receipt = receipt
        self.preset = preset
        self.cutCount = cutCount
        self.captionCount = captionCount
        self.includedSubRip = includedSubRip
        self.loudness = loudness
        self.loudnessVerified = loudnessVerified
        self.appliedGainDb = appliedGainDb
        self.speechCoverage = speechCoverage
        self.completedAt = completedAt
        self.comparison = comparison
    }

    public var storedMetrics: StoredExportMetrics {
        StoredExportMetrics(
            path: receipt.url.path, preset: preset.rawValue, duration: receipt.duration,
            bytes: receipt.bytes, cutCount: cutCount, captionCount: captionCount,
            includedSubRip: includedSubRip, speechCoverage: speechCoverage,
            integratedLUFS: loudness?.integratedLUFS,
            truePeakDbTP: loudness?.truePeakDbTP,
            loudnessRangeLU: loudness?.loudnessRangeLU,
            loudnessVerified: loudnessVerified, appliedGainDb: appliedGainDb,
            completedAt: completedAt)
    }

    public init?(snapshot: ExportHistorySnapshot) {
        let metrics = snapshot.current
        guard let preset = ExportPreset(rawValue: metrics.preset) else { return nil }
        let loudness: LoudnessMeasurement?
        if let integrated = metrics.integratedLUFS, let peak = metrics.truePeakDbTP {
            loudness = LoudnessMeasurement(
                integratedLUFS: integrated, truePeakDbTP: peak,
                loudnessRangeLU: metrics.loudnessRangeLU)
        } else {
            loudness = nil
        }
        self.init(
            receipt: ExportReceipt(
                url: URL(fileURLWithPath: metrics.path), duration: metrics.duration,
                bytes: metrics.bytes),
            preset: preset, cutCount: metrics.cutCount, captionCount: metrics.captionCount,
            includedSubRip: metrics.includedSubRip, loudness: loudness,
            loudnessVerified: metrics.loudnessVerified, appliedGainDb: metrics.appliedGainDb,
            speechCoverage: metrics.speechCoverage, completedAt: metrics.completedAt,
            comparison: snapshot.comparison)
    }
}

extension ExportReport {
    /// The `export.status` fields for this report.
    public var json: [String: JSONValue] {
            var result: [String: JSONValue] = [
                "preset": .string(preset.rawValue),
                "path": .string(receipt.url.path),
                "duration": .number(receipt.duration),
                "bytes": .integer(Int(receipt.bytes)),
                "cuts": .integer(cutCount),
                "captions": .integer(captionCount),
                "includedSRT": .bool(includedSubRip),
                "speechCoverage": .number(speechCoverage),
                "completedAt": .string(ISO8601DateFormatter().string(from: completedAt)),
            ]
            if let comparison = comparison {
                var values: [String: JSONValue] = [
                    "duration": .number(comparison.duration),
                    "bytes": .integer(Int(comparison.bytes)),
                    "cuts": .integer(comparison.cutCount),
                    "captions": .integer(comparison.captionCount),
                    "speechCoverage": .number(comparison.speechCoverage),
                ]
                values["lufs"] = comparison.integratedLUFS.map(JSONValue.number) ?? .null
                result["comparison"] = .object(values)
            } else {
                result["comparison"] = .null
            }
            if let loudness = loudness {
                result["lufs"] = .number(loudness.integratedLUFS)
                result["truePeakDbTP"] = .number(loudness.truePeakDbTP)
                result["loudnessVerified"] = .bool(loudnessVerified)
                if let gain = appliedGainDb { result["normalizationGainDb"] = .number(gain) }
            } else {
                result["lufs"] = .null
            }
            return result
    }
}
