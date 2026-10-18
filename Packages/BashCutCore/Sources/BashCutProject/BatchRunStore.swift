import Foundation

/// The kept batch runs on disk (`~/Library/Application Support/BashCut/Batch/Runs.json`), so the queue, `batch
/// status` and `batch retry` outlive a quit or crash. One JSON file, written whole after each change.
public struct BatchRunStore: Sendable {
    public static let version = 1
    public let file: URL

    public init(file: URL) { self.file = file }

    /// The user store under an Application Support folder.
    public static func user(applicationSupport: URL) -> BatchRunStore {
        BatchRunStore(file: applicationSupport.appendingPathComponent("BashCut/Batch/Runs.json"))
    }

    private struct Contents: Codable {
        var version: Int
        var runs: [BatchRunStatus]
    }

    /// The saved runs, oldest first; none when the file is missing, unreadable or from a newer BashCut. A run that
    /// was not finished when it was saved comes back interrupted.
    public func load(now: Date = Date()) -> [BatchRunStatus] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data), contents.version <= Self.version else {
            return []
        }
        return contents.runs.map { run in
            var run = run
            if !run.state.isFinished { run.markInterrupted(at: now) }
            return run
        }
    }

    public func save(_ runs: [BatchRunStatus]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Contents(version: Self.version, runs: runs))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
