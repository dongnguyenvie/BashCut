import Foundation

/// How the Knowledge window and `knowledge lessons` / `prefs` / `facts` narrow and order entries (#68): by scope,
/// status, tag and text, newest or oldest first.
public struct KnowledgeFilter: Sendable, Equatable {
    public enum Sort: String, Sendable, CaseIterable {
        case newest, oldest
    }

    public var query = ""
    public var scope: KnowledgeScope?
    public var status: LessonStatus?
    public var tag: String?
    public var sort: Sort = .newest

    public init(
        query: String = "", scope: KnowledgeScope? = nil, status: LessonStatus? = nil, tag: String? = nil,
        sort: Sort = .newest
    ) {
        self.query = query
        self.scope = scope
        self.status = status
        self.tag = tag
        self.sort = sort
    }

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Lessons that match, ordered by `updated`; ties keep the file order.
    public func apply(_ lessons: [KnowledgeLesson]) -> [KnowledgeLesson] {
        let needle = needle
        let tag = tag?.lowercased()
        let matching = lessons.filter { lesson in
            (scope == nil || lesson.scope == scope) && (status == nil || lesson.status == status)
                && (tag.map(lesson.tags.contains) ?? true)
                && (needle.isEmpty || ([lesson.title, lesson.symptom, lesson.cause, lesson.fix, lesson.evidence]
                    + lesson.tags).contains { $0.lowercased().contains(needle) })
        }
        return ordered(matching, date: \.updated)
    }

    /// Values that match the scope and text (in the key or the value), ordered by when they were set.
    public func apply(_ values: [KnowledgeValue]) -> [KnowledgeValue] {
        let needle = needle
        let matching = values.filter { value in
            (scope == nil || value.scope == scope)
                && (needle.isEmpty || value.key.lowercased().contains(needle) || value.value.lowercased().contains(needle))
        }
        return ordered(matching, date: \.source.date)
    }

    private func ordered<Entry>(_ entries: [Entry], date: KeyPath<Entry, Date>) -> [Entry] {
        entries.enumerated().sorted { left, right in
            let (a, b) = (left.element[keyPath: date], right.element[keyPath: date])
            guard a != b else { return left.offset < right.offset }
            return sort == .newest ? a > b : a < b
        }.map(\.element)
    }

    /// Every tag the lessons use, sorted.
    public static func tags(_ lessons: [KnowledgeLesson]) -> [String] {
        Array(Set(lessons.flatMap(\.tags))).sorted()
    }

    /// Whether an entry changed after the user last looked (nil: never looked, so nothing is marked new).
    public static func isNew(_ date: Date, since visit: Date?) -> Bool {
        guard let visit else { return false }
        return date > visit
    }
}

extension AgentKnowledgeStore {
    /// Changes whenever a knowledge file of either scope is written, so an open window can reload what agents or
    /// people changed on disk.
    public func signature() -> String {
        let names = ["lessons.json", "prefs.json", "facts.json", "history.jsonl"]
        var parts: [String] = []
        for scope in KnowledgeScope.allCases {
            guard let folder = entriesFolder(scope) else { continue }
            for name in names {
                let url = folder.appendingPathComponent(name)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                parts.append("\(scope.rawValue)/\(name):\(date):\(size)")
            }
        }
        return parts.joined(separator: "|")
    }
}
