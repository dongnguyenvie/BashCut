import BashCutProject
import Foundation

/// What an agent found in a memo (#72): lessons, preferences and facts, as `knowledge split-memo` reads them from a
/// JSON file. Every field but a lesson's title and a value's key and value may be missing.
public struct MemoSplit: Codable, Sendable, Equatable {
    public struct Lesson: Codable, Sendable, Equatable {
        public var title: String
        public var symptom, cause, fix, evidence: String?
        public var tags: [String]?

        public init(
            title: String, symptom: String? = nil, cause: String? = nil, fix: String? = nil, evidence: String? = nil,
            tags: [String]? = nil
        ) {
            self.title = title
            self.symptom = symptom
            self.cause = cause
            self.fix = fix
            self.evidence = evidence
            self.tags = tags
        }
    }

    public struct Value: Codable, Sendable, Equatable {
        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public var lessons: [Lesson]
    public var prefs: [Value]
    public var facts: [Value]

    public init(lessons: [Lesson] = [], prefs: [Value] = [], facts: [Value] = []) {
        self.lessons = lessons
        self.prefs = prefs
        self.facts = facts
    }

    enum CodingKeys: String, CodingKey { case lessons, prefs, facts }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessons = try container.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        prefs = try container.decodeIfPresent([Value].self, forKey: .prefs) ?? []
        facts = try container.decodeIfPresent([Value].self, forKey: .facts) ?? []
    }

    public var isEmpty: Bool { lessons.isEmpty && prefs.isEmpty && facts.isEmpty }

    /// The entries a command received as JSON.
    public init(json: JSONValue) throws {
        do {
            self = try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(json))
        } catch {
            throw KnowledgeError(#"entries must be {"lessons": [{"title", …}], "prefs": [{"key", "value"}], "#
                + #""facts": [{"key", "value"}]}"#)
        }
    }
}

/// The one-time split of a memo, recorded in the scope's `memo-split.json` so it is not offered again. `kept` means
/// the user chose to keep the memo as notes only.
public struct MemoSplitRecord: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case split, kept }

    public var version: Int? = 1
    public var outcome: Outcome
    public var source: KnowledgeSource
    /// What the split proposed; empty when the memo was kept.
    public var lessons: [String] = []
    public var prefs: [String] = []
    public var facts: [String] = []
}

/// What `splitMemo` queued for review, and what it left out because the same entry already exists.
public struct MemoSplitResult: Sendable, Equatable {
    public var lessons: [KnowledgeLesson] = []
    public var values: [KnowledgeValueProposal] = []
    public var skipped: [String] = []
}

/// Splitting the free-text memo into structured entries (#72). The memo itself stays as it is, as Notes; what the
/// split finds waits in the Knowledge inbox (proposed lessons, preference and fact proposals) for the user's review.
extension AgentKnowledgeStore {
    static let splitFile = "memo-split.json"

    public func memoSplitRecord(_ scope: KnowledgeScope) -> MemoSplitRecord? {
        guard let url = entriesFolder(scope)?.appendingPathComponent(Self.splitFile),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(MemoSplitRecord.self, from: data)
    }

    /// Whether to offer the split: the memo has text and was neither split nor kept as notes.
    public func memoNeedsSplit(_ scope: KnowledgeScope) -> Bool {
        guard entriesFolder(scope) != nil, memoSplitRecord(scope) == nil else { return false }
        return !memo(scope).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Queues what an agent found in the `scope` memo for review and records the split. Lessons are added as
    /// proposed; preferences and facts become value proposals in the same scope (facts only in the project). An
    /// entry that already exists (a lesson with the same title, a value with the same key and value) is skipped.
    @discardableResult
    public func splitMemo(_ split: MemoSplit, scope: KnowledgeScope, source: KnowledgeSource) throws -> MemoSplitResult {
        guard entriesFolder(scope) != nil else { throw Self.noProject }
        guard memoSplitRecord(scope) == nil else {
            throw KnowledgeError("The \(scope == .project ? "project memo" : "notes for every project") was already split")
        }
        if scope == .user, !split.facts.isEmpty { throw KnowledgeError("Facts belong to one project") }
        var result = MemoSplitResult()
        let titles = Set(try lessons(scope).map { Self.folded($0.title) })
        var added = Set<String>()
        for lesson in split.lessons {
            let title = lesson.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard !titles.contains(Self.folded(title)), added.insert(Self.folded(title)).inserted else {
                result.skipped.append("lesson: \(title)")
                continue
            }
            result.lessons.append(try addLesson(
                title: title, symptom: lesson.symptom ?? "", cause: lesson.cause ?? "", fix: lesson.fix ?? "",
                evidence: lesson.evidence ?? "", tags: (lesson.tags ?? []) + ["memo"], status: .proposed, scope: scope,
                source: source))
        }
        for (kind, values) in [(KnowledgeValueKind.prefs, split.prefs), (.facts, split.facts)] {
            let current = try self.values(kind, scope: scope)
            for value in values {
                let key = value.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                if current.contains(where: { $0.key == key && $0.value == value.value }) {
                    result.skipped.append("\(kind.rawValue): \(key)")
                    continue
                }
                result.values.append(try proposeValue(kind, key: key, value: value.value, scope: scope, source: source))
            }
        }
        try writeSplitRecord(MemoSplitRecord(
            outcome: .split, source: source, lessons: result.lessons.map(\.id),
            prefs: result.values.filter { $0.kind == .prefs }.map(\.key),
            facts: result.values.filter { $0.kind == .facts }.map(\.key)), scope: scope)
        return result
    }

    /// `pending` (offered), `split`, `kept`, or `none` (an empty memo, or no saved project).
    public func memoSplitState(_ scope: KnowledgeScope) -> String {
        if let record = memoSplitRecord(scope) { return record.outcome.rawValue }
        return memoNeedsSplit(scope) ? "pending" : "none"
    }

    /// The line agents see under a memo that was not split yet.
    public static func splitHint(_ scope: KnowledgeScope) -> String {
        "Not split into lessons, preferences and facts yet: when the user asks, queue what it says for review with "
            + "`bashcut knowledge split-memo <entries.json>\(scope == .user ? " --scope user" : "")`."
    }

    /// What an agent is asked to do when the user asks for the split.
    public static func splitRequest(_ scope: KnowledgeScope) -> String {
        let memo = scope == .project ? "the project memo" : "the notes for every project"
        let flag = scope == .project ? "" : " --scope user"
        return "Split \(memo) into structured knowledge, once. Read it with `bashcut knowledge get`, write what it "
            + "says to a JSON file as lessons (title, symptom, cause, fix, tags), preferences (my taste: key, value)"
            + (scope == .project ? " and project facts (key, value)" : "")
            + ", then run `bashcut knowledge split-memo <file.json>\(flag)`. Keep each entry short and leave long "
            + "notes, such as style measurements, in the memo; do not change the memo. Everything waits in the "
            + "Knowledge inbox for my review."
    }

    /// Keeps the memo as notes only: the split is not offered again.
    public func keepMemo(_ scope: KnowledgeScope, source: KnowledgeSource) throws {
        guard memoSplitRecord(scope) == nil else { return }
        try writeSplitRecord(MemoSplitRecord(outcome: .kept, source: source), scope: scope)
    }

    /// Offers the split again (the record is removed); the entries it proposed stay.
    public func resetMemoSplit(_ scope: KnowledgeScope) throws {
        guard let url = entriesFolder(scope)?.appendingPathComponent(Self.splitFile),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func writeSplitRecord(_ record: MemoSplitRecord, scope: KnowledgeScope) throws {
        try Self.encoder.encode(record).write(to: try folder(scope).appendingPathComponent(Self.splitFile), options: .atomic)
    }

    private static func folded(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
