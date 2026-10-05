import BashCutAgent
import BashCutAutomation
import BashCutProject
import Foundation

/// Skills commands (#71): the agent kit's skills read-only, and the project's and every project's skills to write,
/// turn on or off and delete. Agents' changes to skills every project reads wait for the user's approval.
extension ProjectDocument {
    func registerSkillCommands() {
        handle("skills.list") { document, arguments, _ in
            document.agents.loadKnowledge()
            let origin = try Self.skillOrigin(arguments.optionalString("scope"))
            return .array(KnowledgeSkillRef.Origin.allCases.filter { origin == nil || $0 == origin }
                .flatMap { document.skillsJSON($0) })
        }
        handle("skills.get") { document, arguments, _ in
            document.agents.loadKnowledge()
            let name = try arguments.string("name")
            let origins = try Self.skillOrigin(arguments.optionalString("scope")).map { [$0] }
                ?? KnowledgeSkillRef.Origin.allCases
            let knowledge = document.agents.knowledge
            for origin in origins {
                let ref = KnowledgeSkillRef(origin: origin, name: name)
                guard let text = knowledge.text(of: ref),
                      case .object(var fields)? = document.skillsJSON(origin).first(where: { $0.name == name })
                else { continue }
                fields["text"] = .string(text)
                return .object(fields)
            }
            throw RPCFailure(-32602, "No skill named \(name)")
        }
        handleAuthored("skills.save") { document, arguments, author in
            let scope = try Self.writableSkillScope(arguments)
            let name = try AgentKnowledgeStore.skillName(arguments.string("name"))
            let text = try arguments.string("text")
            let source = Self.knowledgeSource(author, arguments)
            document.agents.loadKnowledge()
            return try document.knowledgeChange(
                "skills.save", approval: scope == .user, author: author, arguments: ["name": name, "scope": scope.rawValue]) {
                try document.agents.knowledge.writeSkill(named: name, text: text, scope: scope, source: source)
                return try document.skillJSON(name, scope: scope)
            }
        }
        for enabled in [true, false] {
            let method = enabled ? "skills.enable" : "skills.disable"
            handleAuthored(method) { document, arguments, author in
                let scope = try Self.writableSkillScope(arguments)
                let name = try arguments.string("name")
                return try document.knowledgeChange(
                    method, approval: scope == .user, author: author, arguments: ["name": name, "scope": scope.rawValue]) {
                    try document.agents.knowledgeStore.setSkillEnabled(name, enabled, scope: scope)
                    document.agents.loadKnowledge()
                    return try document.skillJSON(name, scope: scope)
                }
            }
        }
        handleAuthored("skills.remove") { document, arguments, author in
            let scope = try Self.writableSkillScope(arguments)
            let name = try arguments.string("name")
            let source = Self.knowledgeSource(author, arguments)
            return try document.knowledgeChange(
                "skills.remove", approval: scope == .user, author: author, arguments: ["name": name, "scope": scope.rawValue]) {
                try document.agents.knowledgeStore.removeSkill(named: name, scope: scope, source: source)
                document.agents.loadKnowledge()
                return .bool(true)
            }
        }
        handleAuthored("skills.propose") { document, arguments, author in
            document.agents.loadKnowledge()
            let name = try arguments.string("name")
            guard let before = document.agents.knowledge.kit?.skillText(name) else {
                throw RPCFailure(-32602, "The agent kit has no skill named \(name)")
            }
            let lesson = try document.agents.knowledgeStore.proposeKitChange(
                skill: name, before: before, after: arguments.string("text"), summary: arguments.string("summary"),
                reason: arguments.optionalString("reason") ?? "", source: Self.knowledgeSource(author, arguments))
            document.agents.loadKnowledge()
            if author != .user {
                document.message = String(format: String(localized: "%@ proposes a change to the kit skill %@"),
                                          author.rawValue.capitalized, name)
            }
            return .object(["id": .string(lesson.id), "title": .string(lesson.title), "diff": .string(lesson.fix)])
        }
    }

    /// The skills of one origin as `skills list` shows them.
    private func skillsJSON(_ origin: KnowledgeSkillRef.Origin) -> [JSONValue] {
        let knowledge = agents.knowledge
        guard let scope = KnowledgeScope(rawValue: origin.rawValue) else {
            guard let kit = knowledge.kit else { return [] }
            return kit.skills.map { name in
                let front = SkillFrontMatter(kit.skillText(name) ?? "")
                return .object([
                    "name": .string(name), "scope": .string("kit"), "readOnly": .bool(true),
                    "enabled": .bool(settings.loadAgentKit), "version": .string(kit.version),
                    "description": .string(front.summary), "triggers": .array(front.triggers.map(JSONValue.string)),
                    "path": .string(kit.skillsFolder.appendingPathComponent("\(name)/SKILL.md").path),
                ])
            }
        }
        return knowledge.skills(scope).map { skill in
            let front = SkillFrontMatter((try? String(contentsOf: skill.file, encoding: .utf8)) ?? "")
            var fields: [String: JSONValue] = [
                "name": .string(skill.name), "scope": .string(scope.rawValue), "readOnly": .bool(false),
                "enabled": .bool(skill.enabled), "description": .string(front.summary),
                "path": .string(skill.file.path),
            ]
            if scope == .project {
                fields["claude"] = .bool(skill.claude)
                fields["codex"] = .bool(skill.codex)
            }
            return .object(fields)
        }
    }

    private func skillJSON(_ name: String, scope: KnowledgeScope) throws -> JSONValue {
        guard let origin = KnowledgeSkillRef.Origin(rawValue: scope.rawValue),
              let skill = skillsJSON(origin).first(where: { $0.name == name })
        else { throw RPCFailure(-32602, "No skill named \(name)") }
        return skill
    }

    private static func skillOrigin(_ value: String?) throws -> KnowledgeSkillRef.Origin? {
        guard let value else { return nil }
        guard let origin = KnowledgeSkillRef.Origin(rawValue: value) else {
            throw RPCFailure(-32602, "scope must be kit, user or project")
        }
        return origin
    }

    private static func writableSkillScope(_ arguments: CommandArguments) throws -> KnowledgeScope {
        let value = arguments.optionalString("scope") ?? "project"
        guard let scope = KnowledgeScope(rawValue: value) else {
            throw RPCFailure(-32602, value == "kit"
                ? "Kit skills are read-only; propose a change with skills propose" : "scope must be project or user")
        }
        return scope
    }
}

private extension JSONValue {
    /// The `name` field of an object.
    var name: String? {
        guard case .object(let fields) = self else { return nil }
        return fields["name"]?.string
    }
}
