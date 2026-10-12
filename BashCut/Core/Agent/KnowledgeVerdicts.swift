import BashCutProject
import Foundation

/// What the user did with an agent's change (P3-I1): kept it, undid it, rejected it or edited it. Facts only: each
/// row says which signal BashCut saw (the user dismissed the change notice, undid it, edited the same items, made an
/// unrelated edit, answered the scope guard), never why.
public struct KnowledgeVerdict: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case keep, undo, reject, edit
    }

    /// The signals BashCut records.
    public enum Signal: String, Codable, Sendable, CaseIterable {
        /// The user dismissed the agent-change notice (kept it).
        case dismiss
        /// The user undid the agent's step.
        case undo
        /// The user's next edit changed items the agent's step changed.
        case edit
        /// The user's next edit left the agent's items alone.
        case nextEdit = "next-edit"
        /// The user answered an edit the scope guard held: allowed (keep) or rejected.
        case scopeGuard = "scope-guard"
    }

    public var verdict: Kind
    public var signal: Signal
    /// The command that made the change (`timeline.apply`, `library.apply`, `library.place`, `plan.apply`…) when
    /// BashCut knows it, else `edit`.
    public var subject: String
    /// The change's undo label.
    public var label: String
    /// The agent that made it.
    public var agent: String
    /// The revision the agent's change produced (nil for an edit the scope guard rejected).
    public var rev: Int?
    /// Item IDs involved (the user's overlapping edit, or the agent's change), at most `itemLimit`.
    public var items: [String]?
    public var date: Date

    public static let itemLimit = 20

    public init(
        verdict: Kind, signal: Signal, subject: String?, label: String, agent: String, rev: Int? = nil,
        items: [String] = [], date: Date = Date()
    ) {
        self.verdict = verdict
        self.signal = signal
        self.subject = subject.flatMap { $0.isEmpty ? nil : $0 } ?? "edit"
        self.label = String(label.prefix(120))
        self.agent = agent
        self.rev = rev
        let sorted = items.sorted()
        self.items = sorted.isEmpty ? nil : Array(sorted.prefix(Self.itemLimit))
        self.date = date
    }
}

/// The verdicts of one project, append-only in `.bashcut/knowledge/verdicts.jsonl`.
extension AgentKnowledgeStore {
    static let verdictsFile = "verdicts.jsonl"

    /// Appends one verdict; needs a saved project.
    public func recordVerdict(_ verdict: KnowledgeVerdict) throws {
        let url = try folder(.project).appendingPathComponent(Self.verdictsFile)
        var data = try Self.lineEncoder.encode(verdict)
        data.append(0x0A)
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Every readable verdict, oldest first.
    public func verdicts() -> [KnowledgeVerdict] {
        guard let url = entriesFolder(.project)?.appendingPathComponent(Self.verdictsFile),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n").compactMap { try? Self.decoder.decode(KnowledgeVerdict.self, from: Data($0.utf8)) }
    }

    /// `knowledge verdicts`: counts per subject and verdict over the matching rows, and the newest `limit` rows.
    public func verdictsJSON(verdict: KnowledgeVerdict.Kind? = nil, subject: String? = nil, limit: Int = 20) -> JSONValue {
        let rows = verdicts().filter { (verdict == nil || $0.verdict == verdict) && (subject == nil || $0.subject == subject) }
        var counts: [String: [String: Int]] = [:]
        for row in rows { counts[row.subject, default: [:]][row.verdict.rawValue, default: 0] += 1 }
        let formatter = ISO8601DateFormatter()
        return .object([
            "total": .integer(rows.count),
            "counts": .object(counts.mapValues { .object($0.mapValues(JSONValue.integer)) }),
            "rows": .array(rows.suffix(max(0, limit)).reversed().map { row in
                var fields: [String: JSONValue] = [
                    "verdict": .string(row.verdict.rawValue), "signal": .string(row.signal.rawValue),
                    "subject": .string(row.subject), "label": .string(row.label), "agent": .string(row.agent),
                    "date": .string(formatter.string(from: row.date)),
                ]
                if let rev = row.rev { fields["rev"] = .integer(rev) }
                if let items = row.items { fields["items"] = .array(items.map(JSONValue.string)) }
                return .object(fields)
            }),
        ])
    }

    private static var lineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
