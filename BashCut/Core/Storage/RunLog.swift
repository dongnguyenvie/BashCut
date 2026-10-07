import BashCutProject
import Foundation

/// The run log (P1-D6): an append-only JSON-lines record in `.bashcut/run-log.jsonl` of an agent's run — when it
/// started, the stages it went through, every gate and the user's answer, each review round (fixed, left) and what
/// was measured and what was not. Nothing rewrites or deletes a line; the hand-off report and self-learn read it
/// instead of the chat. A `start` entry opens a new run.
public struct RunLog: Sendable {
    public static let path = ".bashcut/run-log.jsonl"
    /// Longest line kept, so a runaway caller cannot grow the file without bound per call.
    static let maximumLineBytes = 64 * 1_024

    public let url: URL

    public init(projectRoot: URL) {
        url = projectRoot.appendingPathComponent(Self.path)
    }

    /// Appends one entry with its time; returns it as written.
    @discardableResult
    public func append(_ fields: [String: JSONValue], now: Date = Date()) throws -> JSONValue {
        var entry = fields
        entry["time"] = .string(ISO8601DateFormatter().string(from: now))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(JSONValue.object(entry)) + Data("\n".utf8)
        guard data.count <= Self.maximumLineBytes else { throw ProjectError.invalid("Run log entry is too long") }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return .object(entry)
    }

    /// Every readable line in order, each with its index `n` and run number (`run`, 0 before the first `start`).
    public func entries() -> [[String: JSONValue]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var run = 0
        var result: [[String: JSONValue]] = []
        for line in text.split(separator: "\n") {
            guard case .object(var entry)? = try? JSONValue(parsing: Data(line.utf8)) else { continue }
            if entry["kind"] == .string("start") { run += 1 }
            entry["n"] = .integer(result.count)
            entry["run"] = .integer(run)
            result.append(entry)
        }
        return result
    }

    /// Entries of one run (`current` is the last) or all, optionally of one kind, the last `limit`.
    public func read(run: String = "current", kind: String? = nil, limit: Int? = nil) -> JSONValue {
        let all = entries()
        let runs = all.last?["run"]?.int ?? 0
        let wanted: Int? = run == "all" ? nil : run == "current" ? runs : Int(run)
        var rows = all.filter { entry in
            (wanted == nil || entry["run"]?.int == wanted) && (kind == nil || entry["kind"]?.string == kind)
        }
        if let limit, rows.count > limit { rows = Array(rows.suffix(limit)) }
        return .object([
            "path": .string(url.path), "runs": .integer(runs), "run": wanted.map(JSONValue.integer) ?? .string("all"),
            "entries": .array(rows.map(JSONValue.object)),
        ])
    }
}
