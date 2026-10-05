import BashCutAgent
import BashCutAutomation
import BashCutImport
import BashCutPlugin
import BashCutProject
import Foundation

/// Library tools, health checks and agent knowledge shared by their panels and automation.
extension ProjectDocument {
    func runDoctor() async {
        plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent())
        await doctor.run(
            workspace: agents.directory, projectRoot: fileURL?.deletingLastPathComponent(),
            toolsDirectory: agents.toolsDirectory, service: plugins.service,
            pluginDiagnostics: plugins.diagnostics)
    }

    // MARK: Automation

    func registerToolCommands() {
        handleAuthored("luts.import") { document, arguments, author in
            let result = try document.importColorLUT(
                from: URL(fileURLWithPath: arguments.string("path")), name: arguments.optionalString("name"),
                author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "lut": .object(result.lut.fields)])
        }
        handleAuthored("edl.import") { document, arguments, _ in
            let source = URL(fileURLWithPath: try arguments.string("path")).standardizedFileURL
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw RPCFailure(-32602, "No file at \(source.path)")
            }
            try await document.leaveCurrentProject(arguments)
            document.busy = true
            defer { document.busy = false }
            let report = try await document.importLegacyEDL(from: source)
            guard case .object(var result) = document.projectResult() else { return .null }
            result["report"] = report.json
            return .object(result)
        }
        handle("project.recents") { document, _, _ in
            .array(document.settings.recentProjects.map { .string($0.path) })
        }
        handle("doctor.run") { document, _, _ in
            await document.runDoctor()
            return .array(document.doctor.checks.map { check in
                .object([
                    "id": .string(check.id), "title": .string(check.title), "detail": .string(check.detail),
                    "state": .string(["pass", "warning", "fail"][check.state.rawValue]),
                ])
            })
        }
        handle("plugins.health") { document, arguments, _ in
            document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            var selected = document.plugins.plugins
            if let id = arguments.optionalString("plugin") {
                selected = selected.filter { $0.id == id }
                guard !selected.isEmpty else { throw RPCFailure(-32602, "Unknown plugin \(id)") }
            }
            var results: [JSONValue] = []
            for plugin in selected {
                results.append(Self.healthJSON(await document.plugins.checkHealthNow(plugin)))
            }
            return .array(results)
        }
        registerKnowledgeCommands()
    }

    private func registerKnowledgeCommands() {
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
            let scope = try Self.knowledgeScope(arguments.optionalString("scope"))
            let text = try arguments.string("text")
            document.agents.loadKnowledge()
            return try document.knowledgeChange("knowledge.memo", scope: scope, author: author,
                                                arguments: ["scope": scope.rawValue]) {
                try document.agents.knowledge.writeMemo(text, scope: scope)
            }
        }
        handleAuthored("knowledge.skill") { document, arguments, _ in
            document.agents.loadKnowledge()
            try document.agents.knowledge.writeSkill(named: arguments.string("name"), text: arguments.string("text"))
            return .bool(true)
        }
        handleAuthored("knowledge.migrate") { document, arguments, author in
            let scope = try Self.knowledgeScope(arguments.optionalString("to") ?? "user")
            document.agents.loadKnowledge()
            guard let legacy = document.agents.knowledge.legacy else {
                throw RPCFailure(-32602, "No older memo in the agent workspace or home folder")
            }
            return try document.knowledgeChange("knowledge.migrate", scope: scope, author: author,
                                                arguments: ["from": legacy.url.path, "to": scope.rawValue]) {
                try document.agents.knowledge.migrateLegacy(to: scope)
            }
        }
    }

    private static func knowledgeScope(_ value: String?) throws -> KnowledgeScope {
        guard let scope = KnowledgeScope(rawValue: value ?? "project") else {
            throw RPCFailure(-32602, "scope must be project or user")
        }
        return scope
    }

    /// Agents writing the notes every project reads need the user's approval, like the user library.
    private func knowledgeChange(
        _ method: String, scope: KnowledgeScope, author: Author, arguments: [String: String],
        action: @escaping @MainActor () throws -> Void
    ) throws -> JSONValue {
        guard scope == .user, author != .user else {
            try action()
            return .bool(true)
        }
        let request = try queuePrivilegedApproval(method: method, author: author, arguments: arguments, action: action)
        if !request.autoApproved { message = String(localized: "Waiting for approval: \(method)") }
        return request.autoApproved
            ? .bool(true)
            : .object(["approval": .string("pending"), "requestId": .string(request.id.uuidString)])
    }

    private static func healthJSON(_ health: PluginHealth) -> JSONValue {
        .object([
            "plugin": .string(health.pluginID), "state": .string(health.state.rawValue),
            "dependencies": .array(health.dependencies.map { dependency in
                .object([
                    "name": .string(dependency.name), "state": .string("\(dependency.state)"),
                    "detail": .string(dependency.detail),
                ])
            }),
        ])
    }
}
