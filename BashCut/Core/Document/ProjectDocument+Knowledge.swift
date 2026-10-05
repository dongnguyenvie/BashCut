import BashCutAgent
import BashCutAutomation
import BashCutProject
import Foundation

/// Agent knowledge commands: memos and project skills, and the structured lessons, preferences, facts, proposals and
/// history (#67). Agents' writes that every project reads, and decisions on proposals, wait for the user's approval.
extension ProjectDocument {
    func registerKnowledgeCommands() {
        registerMemoCommands()
        registerLessonCommands()
        registerValueCommands()
        registerReviewCommands()
    }

    private func registerMemoCommands() {
        handle("knowledge.get") { document, _, _ in
            document.agents.loadKnowledge()
            let knowledge = document.agents.knowledge
            var result: [String: JSONValue] = [
                "memo": .string(knowledge.memo),
                "userMemo": .string(knowledge.userMemo),
                "project": knowledge.store?.project.map { .string($0.path) } ?? .null,
                "skills": .array(knowledge.skills.map { skill in
                    .object([
                        "name": .string(skill.name), "claude": .bool(skill.claude), "codex": .bool(skill.codex),
                        "path": .string(skill.url.appendingPathComponent("SKILL.md").path),
                        "text": .string((try? String(
                            contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""),
                    ])
                }),
            ]
            if let legacy = knowledge.legacy {
                result["legacy"] = .object(["path": .string(legacy.url.path), "text": .string(legacy.text)])
            }
            return .object(result)
        }
        handleAuthored("knowledge.memo") { document, arguments, author in
            let scope = try Self.knowledgeScope(arguments.optionalString("scope")) ?? .project
            let text = try arguments.string("text")
            document.agents.loadKnowledge()
            return try document.knowledgeChange("knowledge.memo", approval: scope == .user, author: author,
                                                arguments: ["scope": scope.rawValue]) {
                try document.agents.knowledge.writeMemo(text, scope: scope)
                return .bool(true)
            }
        }
        handleAuthored("knowledge.skill") { document, arguments, _ in
            document.agents.loadKnowledge()
            try document.agents.knowledge.writeSkill(named: arguments.string("name"), text: arguments.string("text"))
            return .bool(true)
        }
        handleAuthored("knowledge.migrate") { document, arguments, author in
            let scope = try Self.knowledgeScope(arguments.optionalString("to")) ?? .user
            document.agents.loadKnowledge()
            guard let legacy = document.agents.knowledge.legacy else {
                throw RPCFailure(-32602, "No older memo in the agent workspace or home folder")
            }
            return try document.knowledgeChange("knowledge.migrate", approval: scope == .user, author: author,
                                                arguments: ["from": legacy.url.path, "to": scope.rawValue]) {
                try document.agents.knowledge.migrateLegacy(to: scope)
                return .bool(true)
            }
        }
    }

    private func registerLessonCommands() {
        handle("knowledge.lessons") { document, arguments, _ in
            let filter = KnowledgeFilter(
                query: arguments.optionalString("query") ?? "",
                scope: try Self.knowledgeScope(arguments.optionalString("scope")),
                status: try Self.lessonStatus(arguments.optionalString("status")), tag: arguments.optionalString("tag"),
                sort: arguments.optionalString("sort").flatMap(KnowledgeFilter.Sort.init(rawValue:)) ?? .newest)
            return try .array(filter.apply(document.agents.knowledgeStore.lessons(filter.scope)).map(Self.json))
        }
        handleAuthored("knowledge.add-lesson") { document, arguments, author in
            let scope = try Self.knowledgeScope(arguments.optionalString("scope")) ?? .project
            var status = try Self.lessonStatus(arguments.optionalString("status")) ?? .active
            // Lessons every project reads start as proposals when an agent writes them; the user approves them.
            if scope == .user, author != .user { status = .proposed }
            let lesson = try document.agents.knowledgeStore.addLesson(
                title: arguments.string("title"), symptom: arguments.optionalString("symptom") ?? "",
                cause: arguments.optionalString("cause") ?? "", fix: arguments.optionalString("fix") ?? "",
                evidence: arguments.optionalString("evidence") ?? "", tags: Self.tags(arguments) ?? [],
                status: status, scope: scope, source: Self.knowledgeSource(author, arguments))
            return try Self.json(lesson)
        }
        handleAuthored("knowledge.update-lesson") { document, arguments, author in
            let store = document.agents.knowledgeStore
            let id = try arguments.string("id")
            let lesson = try store.lesson(id)
            let patch = LessonPatch(
                title: arguments.values["title"]?.string, symptom: arguments.values["symptom"]?.string,
                cause: arguments.values["cause"]?.string, fix: arguments.values["fix"]?.string,
                evidence: arguments.values["evidence"]?.string, tags: Self.tags(arguments),
                status: try Self.lessonStatus(arguments.optionalString("status")))
            // Taking a lesson out of review is the user's decision, like knowledge approve.
            let decides = lesson.status == .proposed && patch.status.map { $0 != .proposed } == true
            let source = Self.knowledgeSource(author, arguments)
            return try document.knowledgeChange(
                "knowledge.update-lesson", approval: lesson.scope == .user || decides, author: author,
                arguments: Self.approvalArguments(lesson, arguments)) {
                try Self.json(store.updateLesson(id, patch, source: source))
            }
        }
        handleAuthored("knowledge.remove-lesson") { document, arguments, author in
            let store = document.agents.knowledgeStore
            let lesson = try store.lesson(arguments.string("id"))
            let source = Self.knowledgeSource(author, arguments)
            return try document.knowledgeChange(
                "knowledge.remove-lesson", approval: lesson.scope == .user, author: author,
                arguments: Self.approvalArguments(lesson, arguments)) {
                try Self.json(store.removeLesson(lesson.id, source: source))
            }
        }
    }

    private func registerValueCommands() {
        for kind in KnowledgeValueKind.allCases {
            handle("knowledge.\(kind.rawValue)") { document, arguments, _ in
                let scope = kind == .facts ? .project : try Self.knowledgeScope(arguments.optionalString("scope"))
                let key = arguments.optionalString("key")
                return try .array(document.agents.knowledgeStore.values(kind, scope: scope)
                    .filter { key == nil || $0.key == key }.map(Self.json))
            }
            handleAuthored(Self.setMethod(kind)) { document, arguments, author in
                let scope = kind == .facts ? .project : try Self.knowledgeScope(arguments.optionalString("scope")) ?? .user
                let key = try arguments.string("key")
                let value = arguments.bool("remove") ? nil : arguments.values["value"]?.string
                guard arguments.bool("remove") || value != nil else { throw RPCFailure(-32602, "Missing value") }
                let store = document.agents.knowledgeStore
                let source = Self.knowledgeSource(author, arguments)
                return try document.knowledgeChange(
                    Self.setMethod(kind), approval: scope == .user, author: author,
                    arguments: ["key": key, "value": value ?? "(remove)", "scope": scope.rawValue]) {
                    try store.setValue(kind, key: key, value: value, scope: scope, source: source).map(Self.json) ?? .null
                }
            }
        }
    }

    private func registerReviewCommands() {
        handle("knowledge.proposals") { document, arguments, _ in
            try .array(document.agents.knowledgeStore.proposals(Self.knowledgeScope(arguments.optionalString("scope")))
                .map(Self.json))
        }
        for approve in [true, false] {
            let method = approve ? "knowledge.approve" : "knowledge.reject"
            handleAuthored(method) { document, arguments, author in
                let store = document.agents.knowledgeStore
                let lesson = try store.lesson(arguments.string("id"))
                guard lesson.status == .proposed else { throw RPCFailure(-32602, "Lesson \(lesson.id) is not a proposal") }
                let source = Self.knowledgeSource(author, arguments)
                return try document.knowledgeChange(
                    method, approval: true, author: author, arguments: Self.approvalArguments(lesson, arguments)) {
                    try Self.json(approve ? store.approve(lesson.id, source: source) : store.reject(lesson.id, source: source))
                }
            }
        }
        handle("knowledge.history") { document, arguments, _ in
            try .array(document.agents.knowledgeStore.history(
                Self.knowledgeScope(arguments.optionalString("scope")), limit: arguments.optionalInt("limit") ?? 50)
                .map(Self.json))
        }
    }

    // MARK: Helpers

    private static func setMethod(_ kind: KnowledgeValueKind) -> String {
        kind == .prefs ? "knowledge.set-pref" : "knowledge.set-fact"
    }

    private static func knowledgeScope(_ value: String?) throws -> KnowledgeScope? {
        guard let value else { return nil }
        guard let scope = KnowledgeScope(rawValue: value) else {
            throw RPCFailure(-32602, "scope must be project or user")
        }
        return scope
    }

    private static func lessonStatus(_ value: String?) throws -> LessonStatus? {
        guard let value else { return nil }
        guard let status = LessonStatus(rawValue: value) else {
            throw RPCFailure(-32602, "status must be proposed, active or disabled")
        }
        return status
    }

    private static func tags(_ arguments: CommandArguments) -> [String]? {
        arguments.values["tags"]?.string.map { $0.split(separator: ",").map(String.init) }
    }

    private static func knowledgeSource(_ author: Author, _ arguments: CommandArguments) -> KnowledgeSource {
        KnowledgeSource(agent: author.rawValue, session: arguments.optionalString("session"))
    }

    private static func approvalArguments(_ lesson: KnowledgeLesson, _ arguments: CommandArguments) -> [String: String] {
        var shown = ["id": lesson.id, "title": lesson.title, "scope": lesson.scope.rawValue]
        for (name, value) in arguments.values where name != "id" && name != "session" {
            shown[name == "title" ? "new title" : name] = value.string ?? "\(value)"
        }
        return shown
    }

    private static let entryEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// An entry's stored fields plus the scope it was read from.
    private static func json<Entry: Encodable>(_ entry: Entry, scope: KnowledgeScope) throws -> JSONValue {
        guard case .object(var fields) = try JSONDecoder().decode(JSONValue.self, from: entryEncoder.encode(entry)) else {
            return .null
        }
        fields["scope"] = .string(scope.rawValue)
        return .object(fields)
    }

    private static func json(_ lesson: KnowledgeLesson) throws -> JSONValue { try json(lesson, scope: lesson.scope) }
    private static func json(_ value: KnowledgeValue) throws -> JSONValue { try json(value, scope: value.scope) }
    private static func json(_ change: KnowledgeChange) throws -> JSONValue { try json(change, scope: change.scope) }

    /// Runs `action` now, or, when `approval` is set and an agent asked, after the user approves it.
    private func knowledgeChange(
        _ method: String, approval: Bool, author: Author, arguments: [String: String],
        action: @escaping @MainActor () throws -> JSONValue
    ) throws -> JSONValue {
        guard approval, author != .user else { return try action() }
        var result = JSONValue.bool(true)
        let request = try queuePrivilegedApproval(method: method, author: author, arguments: arguments) {
            result = try action()
        }
        if !request.autoApproved { message = String(localized: "Waiting for approval: \(method)") }
        return request.autoApproved
            ? result
            : .object(["approval": .string("pending"), "requestId": .string(request.id.uuidString)])
    }
}
