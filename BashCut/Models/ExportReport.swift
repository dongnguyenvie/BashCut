import BashCutEngine
import BashCutPlugin
import BashCutStorage
import Foundation

struct ExportReport: Sendable {
    let receipt: ExportReceipt
    let preset: ExportPreset
    let cutCount: Int
    let captionCount: Int
    let includedSubRip: Bool
    let loudness: LoudnessMeasurement?
    let loudnessVerified: Bool
    let appliedGainDb: Double?
    let speechCoverage: Double
    let completedAt: Date
    let comparison: ExportMetricDelta?

    init(
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

    var storedMetrics: StoredExportMetrics {
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

    init?(snapshot: ExportHistorySnapshot) {
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
