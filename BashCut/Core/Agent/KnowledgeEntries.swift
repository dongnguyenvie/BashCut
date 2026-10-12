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
    /// A question the agent asks itself before showing the next draft (#524); nil when the lesson has none.
    public var check: String?
    public var tags: [String]
    public var status: LessonStatus
    public var source: KnowledgeSource
    public var updated: Date
    /// How many times it was seen (P3-I4): 1 when recorded, one more for each `update-lesson --seen`; nil in lessons
    /// written before counting began.
    public var occurrences: Int?
    /// When it was last seen.
    public var lastSeen: Date?
    /// The projects it was seen in, by name, oldest first.
    public var sources: [String]?
    /// The file it was read from; not stored.
    public var scope: KnowledgeScope = .project

    static let sourceLimit = 20

    enum CodingKeys: String, CodingKey {
        case id, title, symptom, cause, fix, evidence, check, tags, status, source, updated, occurrences, lastSeen, sources
    }

    public init(
        id: String, title: String, symptom: String = "", cause: String = "", fix: String = "", evidence: String = "",
        check: String? = nil, tags: [String] = [], status: LessonStatus = .active, source: KnowledgeSource,
        scope: KnowledgeScope = .project
    ) {
        self.id = id
        self.title = title
        self.symptom = symptom
        self.cause = cause
        self.fix = fix
        self.evidence = evidence
        self.check = check.flatMap { $0.isEmpty ? nil : $0 }
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
        check = try container.decodeIfPresent(String.self, forKey: .check).flatMap { $0.isEmpty ? nil : $0 }
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try container.decodeIfPresent(LessonStatus.self, forKey: .status) ?? .active
        source = try container.decodeIfPresent(KnowledgeSource.self, forKey: .source)
            ?? KnowledgeSource(agent: "unknown", date: Date(timeIntervalSince1970: 0))
        updated = try container.decodeIfPresent(Date.self, forKey: .updated) ?? source.date
        occurrences = try container.decodeIfPresent(Int.self, forKey: .occurrences)
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
        sources = try container.decodeIfPresent([String].self, forKey: .sources)
    }

    /// Counts one more sighting at `date`, in the project named `project` when one is open.
    mutating func seen(at date: Date, in project: String?) {
        occurrences = (occurrences ?? 1) + 1
        lastSeen = date
        guard let project, !project.isEmpty else { return }
        var list = sources ?? []
        if !list.contains(project) { list.append(project) }
        sources = Array(list.suffix(Self.sourceLimit))
    }
}

/// Fields to change in a lesson; nil leaves a field as it is.
public struct LessonPatch: Sendable {
    public var title, symptom, cause, fix, evidence, check: String?
    public var tags: [String]?
    public var status: LessonStatus?
    /// Count one more sighting (P3-I4), in this project when one is open.
    public var seen = false
    public var seenIn: String?

    public init(
        title: String? = nil, symptom: String? = nil, cause: String? = nil, fix: String? = nil,
        evidence: String? = nil, check: String? = nil, tags: [String]? = nil, status: LessonStatus? = nil,
        seen: Bool = false, seenIn: String? = nil
    ) {
        self.seen = seen
        self.seenIn = seenIn
        self.title = title
        self.symptom = symptom
        self.cause = cause
        self.fix = fix
        self.evidence = evidence
        self.check = check
        self.tags = tags
        self.status = status
    }

    /// Sets the text fields the patch names, besides the title (an empty check removes it).
    func applyText(to lesson: inout KnowledgeLesson) {
        if let symptom { lesson.symptom = symptom }
        if let cause { lesson.cause = cause }
        if let fix { lesson.fix = fix }
        if let evidence { lesson.evidence = evidence }
        if let check { lesson.check = check.isEmpty ? nil : check }
    }

    public var isEmpty: Bool { onlySeen && !seen }

    /// Changes nothing but the sighting count: the lesson's rule stays as it is.
    public var onlySeen: Bool {
        [title, symptom, cause, fix, evidence, check].allSatisfy { $0 == nil } && tags == nil && status == nil
    }
}

/// Key/value knowledge: the user's taste (`prefs`, either scope; a project value wins over the user's) and facts
/// about one project (`facts`: people, places, footage, what was approved).
public enum KnowledgeValueKind: String, Codable, Sendable, CaseIterable {
    case prefs, facts
}

/// How a preference became known (P3-I4): the user said or approved it, or an agent inferred it.
public enum KnowledgeConfirmation: String, Codable, Sendable, CaseIterable {
    case user, inferred
}

/// Where a fact's value comes from (P3-I4): a source (URL, file, frame, the user), the measurement that gave it (a
/// command or a result path), its sample size and whether it was measured, estimated or said by the user.
public struct KnowledgeFactEvidence: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable { case measured, estimated, user }

    public var source: String?
    public var measure: String?
    public var n: Int?
    public var status: Status?

    public init(source: String? = nil, measure: String? = nil, n: Int? = nil, status: Status? = nil) {
        self.source = source.flatMap { $0.isEmpty ? nil : $0 }
        self.measure = measure.flatMap { $0.isEmpty ? nil : $0 }
        self.n = n
        self.status = status
    }

    public var isEmpty: Bool { source == nil && measure == nil && n == nil && status == nil }
}

/// What a value carries besides its text: a preference's confirmation, a fact's evidence.
public struct KnowledgeValueDetails: Hashable, Sendable {
    public var confirmedBy: KnowledgeConfirmation?
    public var evidence: KnowledgeFactEvidence?

    public init(confirmedBy: KnowledgeConfirmation? = nil, evidence: KnowledgeFactEvidence? = nil) {
        self.confirmedBy = confirmedBy
        self.evidence = evidence.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct KnowledgeValue: Codable, Hashable, Sendable {
    public var key: String
    public var value: String
    public var source: KnowledgeSource
    /// Preferences: whether the user confirmed it or an agent inferred it; nil in values written before.
    public var confirmedBy: KnowledgeConfirmation?
    /// Facts: where the value comes from; nil when nobody said.
    public var evidence: KnowledgeFactEvidence?
    /// The file it was read from; not stored.
    public var scope: KnowledgeScope = .project

    enum CodingKeys: String, CodingKey { case key, value, source, confirmedBy, evidence }

    public init(
        key: String, value: String, source: KnowledgeSource, scope: KnowledgeScope = .project,
        details: KnowledgeValueDetails = KnowledgeValueDetails()
    ) {
        self.key = key
        self.value = value
        self.source = source
        self.scope = scope
        confirmedBy = details.confirmedBy
        evidence = details.evidence
    }

    public var details: KnowledgeValueDetails { KnowledgeValueDetails(confirmedBy: confirmedBy, evidence: evidence) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        source = try container.decodeIfPresent(KnowledgeSource.self, forKey: .source)
            ?? KnowledgeSource(agent: "unknown", date: Date(timeIntervalSince1970: 0))
        confirmedBy = try? container.decodeIfPresent(KnowledgeConfirmation.self, forKey: .confirmedBy)
        evidence = try? container.decodeIfPresent(KnowledgeFactEvidence.self, forKey: .evidence)
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
             ("Evidence", lesson.evidence), ("Check", lesson.check ?? ""), ("Tags", lesson.tags.joined(separator: ", ")),
             ("Status", lesson.status.rawValue)]
                .filter { !$0.1.isEmpty }
                .map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        case .value(let value): value.value
        case .text(let text): text
        }
    }
}
