import Foundation

/// Structured knowledge (#67): lessons, preferences, project facts and their history, as plain JSON files that Claude
/// Code and Codex can read. Project entries live in `<project>/.bashcut/knowledge/`, entries for every project in
/// the user folder (`Application Support/BashCut/Knowledge/`):
///
/// - `lessons.json`, `prefs.json`, `facts.json` (project only): `{"version": 1, "lessons" | "values": [...]}`;
/// - `history.jsonl`: one `KnowledgeChange` per line, newest last.
extension AgentKnowledgeStore {
    static let entriesPath = ".bashcut/knowledge"

    /// The folder of a scope's entries; nil for the project scope when no saved project is open.
    public func entriesFolder(_ scope: KnowledgeScope) -> URL? {
        switch scope {
        case .project: project?.appendingPathComponent(Self.entriesPath, isDirectory: true)
        case .user: user
        }
    }

    private var scopes: [KnowledgeScope] { project == nil ? [.user] : [.project, .user] }

    // MARK: Lessons

    /// Lessons of one scope, or of both (project first) when `scope` is nil.
    public func lessons(_ scope: KnowledgeScope? = nil) throws -> [KnowledgeLesson] {
        try (scope.map { [$0] } ?? scopes).flatMap { scope in
            try readLessons(scope).map { lesson in
                var lesson = lesson
                lesson.scope = scope
                return lesson
            }
        }
    }

    public func lesson(_ id: String) throws -> KnowledgeLesson {
        guard let lesson = try lessons().first(where: { $0.id == id }) else {
            throw KnowledgeError("No lesson \(id)")
        }
        return lesson
    }

    @discardableResult
    public func addLesson(
        title: String, symptom: String = "", cause: String = "", fix: String = "", evidence: String = "",
        tags: [String] = [], status: LessonStatus = .active, scope: KnowledgeScope, source: KnowledgeSource
    ) throws -> KnowledgeLesson {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw KnowledgeError("A lesson needs a title") }
        var all = try readLessons(scope, writable: true)
        let taken = Set(try lessons().map(\.id))
        var id: String
        repeat {
            id = "l-" + UUID().uuidString.prefix(8).lowercased()
        } while taken.contains(id)
        let lesson = KnowledgeLesson(
            id: id, title: title, symptom: symptom, cause: cause, fix: fix, evidence: evidence,
            tags: Self.normalized(tags), status: status, source: source, scope: scope)
        all.append(lesson)
        try writeLessons(all, scope: scope)
        try record(KnowledgeChange(
            action: .add, kind: .lesson, target: id, source: source, before: nil,
            after: .lesson(lesson)), scope: scope)
        return lesson
    }

    /// Changes a lesson's fields. `action` is what history records: `approve` for a proposal set active, `update`
    /// otherwise.
    @discardableResult
    public func updateLesson(
        _ id: String, _ patch: LessonPatch, source: KnowledgeSource, action: KnowledgeChange.Action = .update
    ) throws -> KnowledgeLesson {
        guard !patch.isEmpty else { throw KnowledgeError("Nothing to change") }
        let scope = try lesson(id).scope
        var all = try readLessons(scope, writable: true)
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw KnowledgeError("No lesson \(id)") }
        let before = all[index]
        var lesson = before
        if let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !title.isEmpty else { throw KnowledgeError("A lesson needs a title") }
            lesson.title = title
        }
        if let symptom = patch.symptom { lesson.symptom = symptom }
        if let cause = patch.cause { lesson.cause = cause }
        if let fix = patch.fix { lesson.fix = fix }
        if let evidence = patch.evidence { lesson.evidence = evidence }
        if let tags = patch.tags { lesson.tags = Self.normalized(tags) }
        if let status = patch.status { lesson.status = status }
        lesson.updated = source.date
        lesson.scope = scope
        all[index] = lesson
        try writeLessons(all, scope: scope)
        try record(KnowledgeChange(
            action: action, kind: .lesson, target: id, source: source, before: .lesson(before),
            after: .lesson(lesson)), scope: scope)
        return lesson
    }

    /// Removes a lesson; history keeps it. `action` is `reject` for a declined proposal.
    @discardableResult
    public func removeLesson(
        _ id: String, source: KnowledgeSource, action: KnowledgeChange.Action = .remove
    ) throws -> KnowledgeLesson {
        let lesson = try lesson(id)
        var all = try readLessons(lesson.scope, writable: true)
        all.removeAll { $0.id == id }
        try writeLessons(all, scope: lesson.scope)
        try record(KnowledgeChange(
            action: action, kind: .lesson, target: id, source: source, before: .lesson(lesson),
            after: nil), scope: lesson.scope)
        return lesson
    }

    /// Lessons waiting for review.
    public func proposals(_ scope: KnowledgeScope? = nil) throws -> [KnowledgeLesson] {
        try lessons(scope).filter { $0.status == .proposed }
    }

    public func approve(_ id: String, source: KnowledgeSource) throws -> KnowledgeLesson {
        try requireProposal(id)
        return try updateLesson(id, LessonPatch(status: .active), source: source, action: .approve)
    }

    public func reject(_ id: String, source: KnowledgeSource) throws -> KnowledgeLesson {
        try requireProposal(id)
        return try removeLesson(id, source: source, action: .reject)
    }

    private func requireProposal(_ id: String) throws {
        guard try lesson(id).status == .proposed else { throw KnowledgeError("Lesson \(id) is not a proposal") }
    }

    // MARK: Values

    /// Values of one scope, or of both (project first) when `scope` is nil. Facts exist only in the project.
    public func values(_ kind: KnowledgeValueKind, scope: KnowledgeScope? = nil) throws -> [KnowledgeValue] {
        let scopes = (scope.map { [$0] } ?? scopes).filter { kind == .prefs || $0 == .project }
        return try scopes.flatMap { scope in
            try readValues(kind, scope).map { value in
                var value = value
                value.scope = scope
                return value
            }
        }
    }

    /// Sets a value, or removes it when `value` is nil. Returns the stored value (nil after a removal).
    /// `recordedBy` is who history credits when it is not `source` (the user approving an agent's proposal), and
    /// `action` replaces `set`/`unset` in history.
    @discardableResult
    public func setValue(
        _ kind: KnowledgeValueKind, key: String, value: String?, scope: KnowledgeScope, source: KnowledgeSource,
        recordedBy: KnowledgeSource? = nil, action: KnowledgeChange.Action? = nil
    ) throws -> KnowledgeValue? {
        guard kind == .prefs || scope == .project else { throw KnowledgeError("Facts belong to one project") }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KnowledgeError("A key cannot be empty") }
        var all = try readValues(kind, scope, writable: true)
        let index = all.firstIndex { $0.key == key }
        let before = index.map { all[$0] }
        let historyKind: KnowledgeChange.Kind = kind == .prefs ? .prefs : .facts
        guard let value else {
            guard let index, let before else { throw KnowledgeError("No \(kind.rawValue) key \(key)") }
            all.remove(at: index)
            try writeValues(all, kind: kind, scope: scope)
            try record(KnowledgeChange(
                action: action ?? .unset, kind: historyKind, target: key, source: recordedBy ?? source,
                before: .value(before),
                after: nil), scope: scope)
            return nil
        }
        let entry = KnowledgeValue(key: key, value: value, source: source, scope: scope)
        if let index { all[index] = entry } else { all.append(entry) }
        try writeValues(all, kind: kind, scope: scope)
        try record(KnowledgeChange(
            action: action ?? .set, kind: historyKind, target: key, source: recordedBy ?? source,
            before: before.map(KnowledgeEntry.value),
            after: .value(entry)), scope: scope)
        return entry
    }

    // MARK: History

    /// Changes, newest first, of one scope or both.
    public func history(_ scope: KnowledgeScope? = nil, limit: Int = 50) -> [KnowledgeChange] {
        let changes = (scope.map { [$0] } ?? scopes).flatMap { scope -> [(change: KnowledgeChange, line: Int)] in
            guard let url = entriesFolder(scope)?.appendingPathComponent("history.jsonl"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").enumerated().compactMap { line, text in
                guard var change = try? Self.decoder.decode(KnowledgeChange.self, from: Data(text.utf8)) else {
                    return nil
                }
                change.scope = scope
                return (change, line)
            }
        }
        // Dates have whole seconds, so later lines of the same file win ties.
        return Array(changes.sorted {
            $0.change.source.date != $1.change.source.date
                ? $0.change.source.date > $1.change.source.date : $0.line > $1.line
        }.prefix(limit).map(\.change))
    }

    func record(_ change: KnowledgeChange, scope: KnowledgeScope) throws {
        let url = try folder(scope).appendingPathComponent("history.jsonl")
        let encoder = Self.encoder
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(change)
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    // MARK: Files

    private struct LessonFile: Codable {
        var version: Int? = 1
        var lessons: [KnowledgeLesson]
    }

    private struct ValueFile: Codable {
        var version: Int? = 1
        var values: [KnowledgeValue]
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The scope's folder, created on first write.
    func folder(_ scope: KnowledgeScope) throws -> URL {
        guard let folder = entriesFolder(scope) else { throw Self.noProject }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A missing file is empty; a file that cannot be read fails, so a write never replaces entries it could not
    /// parse.
    func read<File: Decodable>(_ name: String, scope: KnowledgeScope, writable: Bool) throws -> File? {
        guard let folder = entriesFolder(scope) else {
            if writable { throw Self.noProject }
            return nil
        }
        let url = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(File.self, from: data)
        } catch {
            throw KnowledgeError("Cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    private func readLessons(_ scope: KnowledgeScope, writable: Bool = false) throws -> [KnowledgeLesson] {
        let file: LessonFile? = try read("lessons.json", scope: scope, writable: writable)
        return file?.lessons ?? []
    }

    private func writeLessons(_ lessons: [KnowledgeLesson], scope: KnowledgeScope) throws {
        try Self.encoder.encode(LessonFile(lessons: lessons))
            .write(to: try folder(scope).appendingPathComponent("lessons.json"), options: .atomic)
    }

    private func readValues(
        _ kind: KnowledgeValueKind, _ scope: KnowledgeScope, writable: Bool = false
    ) throws -> [KnowledgeValue] {
        let file: ValueFile? = try read("\(kind.rawValue).json", scope: scope, writable: writable)
        return file?.values ?? []
    }

    private func writeValues(_ values: [KnowledgeValue], kind: KnowledgeValueKind, scope: KnowledgeScope) throws {
        try Self.encoder.encode(ValueFile(values: values))
            .write(to: try folder(scope).appendingPathComponent("\(kind.rawValue).json"), options: .atomic)
    }
}
