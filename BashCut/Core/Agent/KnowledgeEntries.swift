import Foundation

/// Who wrote a knowledge entry or change: the author (`user`, `claude`, `codex`, `agent`…), the agent's session when
/// it gave one, and when.
public struct KnowledgeSource: Codable, Hashable, Sendable {
    public var agent: String
    public var session: String?
    public var date: Date

    public init(agent: String, session: String? = nil, date: Date = Date()) {
        self.agent = agent
        self.session = session
        self.date = date
    }
}

public enum LessonStatus: String, Codable, Sendable, CaseIterable {
    /// Waiting for the user's review (the proposals inbox); agents do not follow it yet.
    case proposed
    case active
    /// Kept for the record; agents do not follow it.
    case disabled
}

/// One thing the agent learned: what went wrong, why, and what to do next time (#67).
public struct KnowledgeLesson: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symptom: String
    public var cause: String
    /// What to do next time.
    public var fix: String
    public var evidence: String
    public var tags: [String]
    public var status: LessonStatus
    public var source: KnowledgeSource
    public var updated: Date
    /// The file it was read from; not stored.
    public var scope: KnowledgeScope = .project

    enum CodingKeys: String, CodingKey { case id, title, symptom, cause, fix, evidence, tags, status, source, updated }

    public init(
        id: String, title: String, symptom: String = "", cause: String = "", fix: String = "", evidence: String = "",
        tags: [String] = [], status: LessonStatus = .active, source: KnowledgeSource, scope: KnowledgeScope = .project
    ) {
        self.id = id
        self.title = title
        self.symptom = symptom
        self.cause = cause
        self.fix = fix
        self.evidence = evidence
        self.tags = tags
        self.status = status
        self.source = source
        updated = source.date
        self.scope = scope
    }

    /// Agents and people edit these files by hand, so everything but the ID and title may be missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symptom = try container.decodeIfPresent(String.self, forKey: .symptom) ?? ""
        cause = try container.decodeIfPresent(String.self, forKey: .cause) ?? ""
        fix = try container.decodeIfPresent(String.self, forKey: .fix) ?? ""
        evidence = try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try container.decodeIfPresent(LessonStatus.self, forKey: .status) ?? .active
        source = try container.decodeIfPresent(KnowledgeSource.self, forKey: .source)
            ?? KnowledgeSource(agent: "unknown", date: Date(timeIntervalSince1970: 0))
        updated = try container.decodeIfPresent(Date.self, forKey: .updated) ?? source.date
    }
}

/// Fields to change in a lesson; nil leaves a field as it is.
public struct LessonPatch: Sendable {
    public var title, symptom, cause, fix, evidence: String?
    public var tags: [String]?
    public var status: LessonStatus?

    public init(
        title: String? = nil, symptom: String? = nil, cause: String? = nil, fix: String? = nil,
        evidence: String? = nil, tags: [String]? = nil, status: LessonStatus? = nil
    ) {
        self.title = title
        self.symptom = symptom
        self.cause = cause
        self.fix = fix
        self.evidence = evidence
        self.tags = tags
        self.status = status
    }

    public var isEmpty: Bool {
        [title, symptom, cause, fix, evidence].allSatisfy { $0 == nil } && tags == nil && status == nil
    }
}

/// Key/value knowledge: the user's taste (`prefs`, either scope; a project value wins over the user's) and facts
/// about one project (`facts`: people, places, footage, what was approved).
public enum KnowledgeValueKind: String, Codable, Sendable, CaseIterable {
    case prefs, facts
}

public struct KnowledgeValue: Codable, Hashable, Sendable {
    public var key: String
    public var value: String
    public var source: KnowledgeSource
    /// The file it was read from; not stored.
    public var scope: KnowledgeScope = .project

    enum CodingKeys: String, CodingKey { case key, value, source }

    public init(key: String, value: String, source: KnowledgeSource, scope: KnowledgeScope = .project) {
        self.key = key
        self.value = value
        self.source = source
        self.scope = scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        source = try container.decodeIfPresent(KnowledgeSource.self, forKey: .source)
            ?? KnowledgeSource(agent: "unknown", date: Date(timeIntervalSince1970: 0))
    }
}

/// One line of `history.jsonl`: what changed, who changed it and the entry before and after (nil when it was added
/// or removed), so the Knowledge window can show a diff and revert it (#70).
public struct KnowledgeChange: Codable, Hashable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable { case add, update, remove, approve, reject, set, unset, revert }
    public enum Kind: String, Codable, Sendable { case lesson, prefs, facts, memo, skill }

    public var id = UUID().uuidString.lowercased()
    public var action: Action
    public var kind: Kind
    /// The lesson ID, the key, the skill name, or `memo`.
    public var target: String
    public var source: KnowledgeSource
    public var before: KnowledgeEntry?
    public var after: KnowledgeEntry?
    /// The file it was read from; not stored.
    public var scope: KnowledgeScope = .project

    enum CodingKeys: String, CodingKey { case id, action, kind, target, source, before, after }

    /// Whether `revert` can undo it. Rejecting a preference proposal changed no stored value, so there is nothing to
    /// put back.
    public var isRevertible: Bool { !(action == .reject && (kind == .prefs || kind == .facts)) }
}

/// A lesson, a value, or the text of a memo or skill (`{"text": …}`), as history stores it.
public enum KnowledgeEntry: Codable, Hashable, Sendable {
    case lesson(KnowledgeLesson)
    case value(KnowledgeValue)
    case text(String)

    private enum TextKeys: String, CodingKey { case text }

    public init(from decoder: Decoder) throws {
        if let lesson = try? KnowledgeLesson(from: decoder) {
            self = .lesson(lesson)
        } else if let value = try? KnowledgeValue(from: decoder) {
            self = .value(value)
        } else {
            self = .text(try decoder.container(keyedBy: TextKeys.self).decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .lesson(let lesson): try lesson.encode(to: encoder)
        case .value(let value): try value.encode(to: encoder)
        case .text(let text):
            var container = encoder.container(keyedBy: TextKeys.self)
            try container.encode(text, forKey: .text)
        }
    }

    /// The entry as lines a diff compares: a lesson's fields one per line, a value, or the text.
    public var diffText: String {
        switch self {
        case .lesson(let lesson):
            [("Title", lesson.title), ("Symptom", lesson.symptom), ("Cause", lesson.cause), ("Fix", lesson.fix),
             ("Evidence", lesson.evidence), ("Tags", lesson.tags.joined(separator: ", ")),
             ("Status", lesson.status.rawValue)]
                .filter { !$0.1.isEmpty }
                .map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        case .value(let value): value.value
        case .text(let text): text
        }
    }
}
