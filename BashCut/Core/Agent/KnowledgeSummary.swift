import BashCutProject
import Foundation

/// What every agent session starts with (#73): the active lessons, the preferences (a project value wins over the
/// user's) and the project facts, bounded so a large knowledge base cannot crowd the prompt. Proposals are only
/// counted; agents do not follow them until the user approves them. `context get` returns `json`, and terminal and
/// chat agents get `text` in their session context.
public struct KnowledgeSummary: Sendable, Equatable {
    public static let lessonLimit = 20
    public static let valueLimit = 30
    /// Longest text of one field; longer text ends in "…".
    public static let fieldLimit = 240

    /// Active lessons, project first, newest first within a scope.
    public var lessons: [KnowledgeLesson] = []
    public var prefs: [KnowledgeValue] = []
    /// The `creator.*` preferences as one profile (P3-I5); they are not repeated in `prefs`.
    public var creator: JSONValue?
    public var facts: [KnowledgeValue] = []
    /// Entries left out by the limits.
    public var omittedLessons = 0, omittedPrefs = 0, omittedFacts = 0
    public var proposals = 0
    /// Files that could not be read, with the reason.
    public var errors: [String] = []

    public var isEmpty: Bool {
        lessons.isEmpty && prefs.isEmpty && creator == nil && facts.isEmpty && proposals == 0 && errors.isEmpty
    }

    public var json: JSONValue {
        func value(_ value: KnowledgeValue) -> JSONValue {
            var row: [String: JSONValue] = [
                "key": .string(value.key), "value": .string(Self.clip(value.value)), "scope": .string(value.scope.rawValue),
            ]
            if let confirmedBy = value.confirmedBy { row["confirmedBy"] = .string(confirmedBy.rawValue) }
            if let evidence = value.evidence {
                if let status = evidence.status { row["status"] = .string(status.rawValue) }
                if let n = evidence.n { row["n"] = .integer(n) }
                if let source = evidence.source { row["source"] = .string(Self.clip(source, limit: 120)) }
                if let measure = evidence.measure { row["measure"] = .string(Self.clip(measure, limit: 120)) }
            }
            return .object(row)
        }
        return .object([
            "lessons": .array(lessons.map { lesson in
                var row: [String: JSONValue] = [
                    "id": .string(lesson.id), "title": .string(Self.clip(lesson.title)),
                    "fix": .string(Self.clip(lesson.fix)), "tags": .array(lesson.tags.map(JSONValue.string)),
                    "scope": .string(lesson.scope.rawValue),
                ]
                if let check = lesson.check { row["check"] = .string(Self.clip(check)) }
                if let occurrences = lesson.occurrences { row["occurrences"] = .integer(occurrences) }
                if let lastSeen = lesson.lastSeen { row["lastSeen"] = .string(Self.day(lastSeen)) }
                if let sources = lesson.sources, sources.count > 1 { row["sources"] = .integer(sources.count) }
                return .object(row)
            }),
            "prefs": .array(prefs.map(value)), "facts": .array(facts.map(value)), "creator": creator ?? .null,
            "omitted": .object([
                "lessons": .integer(omittedLessons), "prefs": .integer(omittedPrefs), "facts": .integer(omittedFacts),
            ]),
            "proposals": .integer(proposals), "errors": .array(errors.map(JSONValue.string)),
        ])
    }

    public var text: String {
        var lines = ["[Knowledge]"]
        if isEmpty {
            lines.append("No lessons, preferences or facts yet.")
        } else {
            lines.append("Follow these; `bashcut knowledge lessons`, `prefs` and `facts` give the details.")
        }
        if !lessons.isEmpty {
            lines.append("Lessons:")
            lines += lessons.map { lesson in
                "- \(lesson.id) (\(lesson.scope.rawValue)) \(Self.clip(lesson.title))"
                    + (lesson.fix.isEmpty ? "" : " → \(Self.clip(lesson.fix))")
                    + (lesson.check.map { " (check: \(Self.clip($0)))" } ?? "")
                    + Self.seenText(lesson)
            }
            if omittedLessons > 0 { lines.append("- … \(omittedLessons) more (`bashcut knowledge lessons --status active`)") }
        }
        if let creator = creator?.object, !creator.isEmpty {
            lines.append("Creator: " + creator.keys.sorted().map { key in
                let value = creator[key]?.string ?? creator[key]?.array.compactMap(\.string).joined(separator: ", ") ?? ""
                return "\(key) = \(Self.clip(value, limit: 80))"
            }.joined(separator: "; "))
        }
        if !prefs.isEmpty {
            lines.append("Preferences:")
            lines += prefs.map {
                "- \($0.key) = \(Self.clip($0.value)) (\($0.scope.rawValue)"
                    + ($0.confirmedBy == .inferred ? ", inferred)" : ")")
            }
            if omittedPrefs > 0 { lines.append("- … \(omittedPrefs) more (`bashcut knowledge prefs`)") }
        }
        if !facts.isEmpty {
            lines.append("Project facts:")
            lines += facts.map { "- \($0.key) = \(Self.clip($0.value))" + Self.evidenceText($0.evidence) }
            if omittedFacts > 0 { lines.append("- … \(omittedFacts) more (`bashcut knowledge facts`)") }
        }
        if proposals > 0 {
            lines.append("\(proposals) proposal(s) (lessons, preference changes) wait for the user's review in the "
                + "Knowledge inbox; do not follow them yet.")
        }
        lines += errors.map { "Unreadable: \($0)" }
        lines.append(
            "Record what you learn with `bashcut knowledge add-lesson` (use --status proposed when unsure), the user's "
                + "taste with `knowledge set-pref` and project facts with `knowledge set-fact`.")
        lines.append("[/Knowledge]")
        return lines.joined(separator: "\n")
    }

    /// One line of at most `limit` characters.
    static func clip(_ text: String, limit: Int = fieldLimit) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    static func day(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// " [seen 3×, last 2026-10-01, 2 projects]" for a lesson seen more than once.
    static func seenText(_ lesson: KnowledgeLesson) -> String {
        guard let occurrences = lesson.occurrences, occurrences > 1 else { return "" }
        var parts = ["seen \(occurrences)×"]
        if let lastSeen = lesson.lastSeen { parts.append("last \(day(lastSeen))") }
        if let sources = lesson.sources, sources.count > 1 { parts.append("\(sources.count) projects") }
        return " [" + parts.joined(separator: ", ") + "]"
    }

    /// " [measured, n=12]" for a fact with evidence.
    static func evidenceText(_ evidence: KnowledgeFactEvidence?) -> String {
        guard let evidence else { return "" }
        let parts = [evidence.status?.rawValue, evidence.n.map { "n=\($0)" }].compactMap { $0 }
        return parts.isEmpty ? "" : " [" + parts.joined(separator: ", ") + "]"
    }
}

extension AgentKnowledgeStore {
    /// The summary of both scopes. A file that cannot be read is reported in `errors` and skipped, so the rest of
    /// the knowledge still reaches the agent.
    public func summary() -> KnowledgeSummary {
        var summary = KnowledgeSummary()
        let scopes: [KnowledgeScope] = project == nil ? [.user] : [.project, .user]
        var lessons: [KnowledgeLesson] = []
        for scope in scopes {
            do {
                let all = try self.lessons(scope)
                lessons += all.filter { $0.status == .active }.sorted { $0.updated > $1.updated }
                summary.proposals += all.filter { $0.status == .proposed }.count
            } catch { summary.errors.append(error.localizedDescription) }
        }
        do { summary.proposals += try valueProposals().count } catch { summary.errors.append(error.localizedDescription) }
        summary.lessons = Array(lessons.prefix(KnowledgeSummary.lessonLimit))
        summary.omittedLessons = lessons.count - summary.lessons.count

        func values(_ kind: KnowledgeValueKind) -> [KnowledgeValue] {
            var result: [KnowledgeValue] = []
            for scope in scopes where kind == .prefs || scope == .project {
                do {
                    let taken = Set(result.map(\.key))
                    result += try self.values(kind, scope: scope).filter { !taken.contains($0.key) }
                } catch { summary.errors.append(error.localizedDescription) }
            }
            return result
        }
        let all = values(.prefs)
        summary.creator = CreatorProfile.json(all)
        let prefs = all.filter { !CreatorProfile.isCreatorKey($0.key) }
        summary.prefs = Array(prefs.prefix(KnowledgeSummary.valueLimit))
        summary.omittedPrefs = prefs.count - summary.prefs.count
        let facts = values(.facts)
        summary.facts = Array(facts.prefix(KnowledgeSummary.valueLimit))
        summary.omittedFacts = facts.count - summary.facts.count
        return summary
    }
}
