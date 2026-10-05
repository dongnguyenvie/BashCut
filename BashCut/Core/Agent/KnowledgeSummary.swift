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
    public var facts: [KnowledgeValue] = []
    /// Entries left out by the limits.
    public var omittedLessons = 0, omittedPrefs = 0, omittedFacts = 0
    public var proposals = 0
    /// Files that could not be read, with the reason.
    public var errors: [String] = []

    public var isEmpty: Bool { lessons.isEmpty && prefs.isEmpty && facts.isEmpty && proposals == 0 && errors.isEmpty }

    public var json: JSONValue {
        func value(_ value: KnowledgeValue) -> JSONValue {
            .object(["key": .string(value.key), "value": .string(Self.clip(value.value)), "scope": .string(value.scope.rawValue)])
        }
        return .object([
            "lessons": .array(lessons.map { lesson in
                .object([
                    "id": .string(lesson.id), "title": .string(Self.clip(lesson.title)),
                    "fix": .string(Self.clip(lesson.fix)), "tags": .array(lesson.tags.map(JSONValue.string)),
                    "scope": .string(lesson.scope.rawValue),
                ])
            }),
            "prefs": .array(prefs.map(value)), "facts": .array(facts.map(value)),
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
            }
            if omittedLessons > 0 { lines.append("- … \(omittedLessons) more (`bashcut knowledge lessons --status active`)") }
        }
        if !prefs.isEmpty {
            lines.append("Preferences:")
            lines += prefs.map { "- \($0.key) = \(Self.clip($0.value)) (\($0.scope.rawValue))" }
            if omittedPrefs > 0 { lines.append("- … \(omittedPrefs) more (`bashcut knowledge prefs`)") }
        }
        if !facts.isEmpty {
            lines.append("Project facts:")
            lines += facts.map { "- \($0.key) = \(Self.clip($0.value))" }
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

    /// One line of at most `fieldLimit` characters.
    static func clip(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return line.count > fieldLimit ? String(line.prefix(fieldLimit - 1)) + "…" : line
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
        let prefs = values(.prefs)
        summary.prefs = Array(prefs.prefix(KnowledgeSummary.valueLimit))
        summary.omittedPrefs = prefs.count - summary.prefs.count
        let facts = values(.facts)
        summary.facts = Array(facts.prefix(KnowledgeSummary.valueLimit))
        summary.omittedFacts = facts.count - summary.facts.count
        return summary
    }
}
