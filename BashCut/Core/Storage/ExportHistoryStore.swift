import Foundation

public struct StoredExportMetrics: Codable, Sendable, Equatable {
    public let path: String
    public let preset: String
    public let duration: Double
    public let bytes: Int64
    public let cutCount: Int
    public let captionCount: Int
    public let includedSubRip: Bool
    public let speechCoverage: Double
    public let integratedLUFS: Double?
    public let truePeakDbTP: Double?
    public let loudnessRangeLU: Double?
    public let loudnessVerified: Bool
    public let appliedGainDb: Double?
    public let completedAt: Date

    public init(
        path: String, preset: String, duration: Double, bytes: Int64, cutCount: Int,
        captionCount: Int, includedSubRip: Bool, speechCoverage: Double,
        integratedLUFS: Double?, truePeakDbTP: Double?, loudnessRangeLU: Double?,
        loudnessVerified: Bool, appliedGainDb: Double?, completedAt: Date
    ) {
        self.path = path
        self.preset = preset
        self.duration = duration
        self.bytes = bytes
        self.cutCount = cutCount
        self.captionCount = captionCount
        self.includedSubRip = includedSubRip
        self.speechCoverage = speechCoverage
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
        self.loudnessVerified = loudnessVerified
        self.appliedGainDb = appliedGainDb
        self.completedAt = completedAt
    }
}

public struct ExportMetricDelta: Sendable, Equatable {
    public let duration: Double
    public let bytes: Int64
    public let cutCount: Int
    public let captionCount: Int
    public let speechCoverage: Double
    public let integratedLUFS: Double?
}

public struct ExportHistorySnapshot: Sendable, Equatable {
    public let current: StoredExportMetrics
    public let comparison: ExportMetricDelta?
}

public struct ExportHistoryStore: Sendable {
    private let limit: Int

    public init(limit: Int = 20) { self.limit = max(2, limit) }

    public func record(_ metrics: StoredExportMetrics, projectRoot: URL) throws
        -> ExportHistorySnapshot
    {
        var history = (try? read(projectRoot: projectRoot)) ?? []
        let comparison = history.last.map { Self.compare(metrics, with: $0) }
        history.append(metrics)
        if history.count > limit { history.removeFirst(history.count - limit) }
        let url = historyURL(projectRoot: projectRoot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(history).write(to: url, options: .atomic)
        return ExportHistorySnapshot(current: metrics, comparison: comparison)
    }

    public func latest(projectRoot: URL) throws -> ExportHistorySnapshot? {
        let history = try read(projectRoot: projectRoot)
        guard let current = history.last else { return nil }
        let comparison = history.dropLast().last.map { Self.compare(current, with: $0) }
        return ExportHistorySnapshot(current: current, comparison: comparison)
    }

    private func read(projectRoot: URL) throws -> [StoredExportMetrics] {
        let url = historyURL(projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder().decode([StoredExportMetrics].self, from: Data(contentsOf: url))
    }

    private func historyURL(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".bashcut/export-history.json")
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func compare(
        _ current: StoredExportMetrics, with previous: StoredExportMetrics
    ) -> ExportMetricDelta {
        let loudnessDelta: Double?
        if let currentLUFS = current.integratedLUFS, let previousLUFS = previous.integratedLUFS {
            loudnessDelta = currentLUFS - previousLUFS
        } else {
            loudnessDelta = nil
        }
        return ExportMetricDelta(
            duration: current.duration - previous.duration,
            bytes: current.bytes - previous.bytes,
            cutCount: current.cutCount - previous.cutCount,
            captionCount: current.captionCount - previous.captionCount,
            speechCoverage: current.speechCoverage - previous.speechCoverage,
            integratedLUFS: loudnessDelta)
    }
}
