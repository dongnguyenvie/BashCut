import BashCutProject
import Foundation

/// Where an export was posted (P3-I2): `export link --url --platform --posted-at`.
public struct ExportLink: Codable, Sendable, Equatable {
    public var url: String
    public var platform: String?
    /// When it went live, as given (an ISO 8601 date or date-time).
    public var postedAt: String?
    public var addedAt: Date

    public init(url: String, platform: String? = nil, postedAt: String? = nil, addedAt: Date = Date()) {
        self.url = url
        self.platform = platform
        self.postedAt = postedAt
        self.addedAt = addedAt
    }
}

/// What the timeline was when an export was made, kept beside the ledger in `.bashcut/exports/<id>.json` for
/// `outcomes map`: the sections and the caption words in timeline seconds.
public struct ExportSnapshot: Codable, Sendable, Equatable {
    public struct Section: Codable, Sendable, Equatable {
        public var label: String
        public var start: Double
        public var end: Double
    }

    public struct Word: Codable, Sendable, Equatable {
        public var text: String
        public var start: Double
        public var end: Double
    }

    public var id: String
    public var rev: Int
    public var sections: [Section]
    public var words: [Word]

    public init(id: String, project: Project) {
        self.id = id
        rev = project.revision
        sections = ProjectFingerprint.sections(project).map { Section(label: $0.label, start: $0.start, end: $0.end) }
        words = ProjectFingerprint.words(project).map { Word(text: $0.text, start: $0.start, end: $0.end) }
    }
}

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
    /// Review issues the project kept with a reason when it was exported (P1-E2), by issue ID.
    public var acceptedIssues: [String: String]?
    /// The ledger (P3-I2): an ID (`x-…`), the revision exported, the edit's fingerprint and where it was posted. Nil
    /// in entries written before.
    public var id: String?
    public var rev: Int?
    public var fingerprint: JSONValue?
    public var links: [ExportLink]?

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

    public init(limit: Int = 100) { self.limit = max(2, limit) }

    /// Appends a finished export; with `project` (the timeline exported) it gets an ID, its revision, the fingerprint
    /// and a snapshot of its sections and words. Entries past the limit are dropped with their snapshots.
    public func record(_ metrics: StoredExportMetrics, projectRoot: URL, project: Project? = nil) throws
        -> ExportHistorySnapshot
    {
        var metrics = metrics
        var history = (try? read(projectRoot: projectRoot)) ?? []
        if let project {
            let taken = Set(history.compactMap(\.id))
            var id: String
            repeat { id = "x-" + UUID().uuidString.prefix(8).lowercased() } while taken.contains(id)
            metrics.id = id
            metrics.rev = project.revision
            metrics.fingerprint = ProjectFingerprint.json(project)
            try? writeSnapshot(ExportSnapshot(id: id, project: project), projectRoot: projectRoot)
        }
        let comparison = history.last.map { Self.compare(metrics, with: $0) }
        history.append(metrics)
        if history.count > limit {
            for dropped in history.prefix(history.count - limit) {
                if let id = dropped.id { try? FileManager.default.removeItem(at: snapshotURL(id, projectRoot: projectRoot)) }
            }
            history.removeFirst(history.count - limit)
        }
        try write(history, projectRoot: projectRoot)
        return ExportHistorySnapshot(current: metrics, comparison: comparison)
    }

    /// The export `reference` names (its ID, its 0-based index in the ledger or its path), or the latest one.
    public func entry(_ reference: String?, projectRoot: URL) throws -> (index: Int, entry: StoredExportMetrics) {
        let history = try read(projectRoot: projectRoot)
        guard !history.isEmpty else { throw ProjectError.invalid("No export recorded in this project yet") }
        guard let reference, !reference.isEmpty else { return (history.count - 1, history[history.count - 1]) }
        let index = history.firstIndex { $0.id == reference || $0.path == reference }
            ?? Int(reference).flatMap { history.indices.contains($0) ? $0 : nil }
        guard let index else { throw ProjectError.invalid("No export \(reference) (export history lists them)") }
        return (index, history[index])
    }

    /// Adds where the export was posted; the same URL again replaces its platform and date.
    public func addLink(_ link: ExportLink, to reference: String?, projectRoot: URL) throws -> StoredExportMetrics {
        var history = try read(projectRoot: projectRoot)
        let index = try entry(reference, projectRoot: projectRoot).index
        var links = history[index].links ?? []
        links.removeAll { $0.url == link.url }
        links.append(link)
        history[index].links = links
        try write(history, projectRoot: projectRoot)
        return history[index]
    }

    public func snapshot(_ id: String, projectRoot: URL) -> ExportSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(id, projectRoot: projectRoot)) else { return nil }
        return try? decoder().decode(ExportSnapshot.self, from: data)
    }

    private func writeSnapshot(_ snapshot: ExportSnapshot, projectRoot: URL) throws {
        let url = snapshotURL(snapshot.id, projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private func snapshotURL(_ id: String, projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".bashcut/exports/\(id).json")
    }

    private func write(_ history: [StoredExportMetrics], projectRoot: URL) throws {
        let url = historyURL(projectRoot: projectRoot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(history).write(to: url, options: .atomic)
    }

    public func latest(projectRoot: URL) throws -> ExportHistorySnapshot? {
        let history = try read(projectRoot: projectRoot)
        guard let current = history.last else { return nil }
        let comparison = history.dropLast().last.map { Self.compare(current, with: $0) }
        return ExportHistorySnapshot(current: current, comparison: comparison)
    }

    /// Every recorded export, oldest first (the last `limit`).
    public func all(projectRoot: URL) throws -> [StoredExportMetrics] { try read(projectRoot: projectRoot) }

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
