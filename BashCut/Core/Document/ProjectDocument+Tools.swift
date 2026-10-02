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
            toolsDirectory: agents.toolsDirectory, plugins: plugins.plugins,
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
            let knowledge = document.agents.knowledge
            knowledge.load(from: document.agents.directory)
            return .object([
                "memo": .string(knowledge.memo),
                "skills": .array(knowledge.skills.map { skill in
                    .object([
                        "name": .string(skill.name), "claude": .bool(skill.claude), "codex": .bool(skill.codex),
                        "text": .string((try? String(
                            contentsOf: skill.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""),
                    ])
                }),
            ])
        }
        handleAuthored("knowledge.memo") { document, arguments, _ in
            let knowledge = document.agents.knowledge
            knowledge.load(from: document.agents.directory)
            try knowledge.writeMemo(arguments.string("text"))
            return .bool(true)
        }
        handleAuthored("knowledge.skill") { document, arguments, _ in
            let knowledge = document.agents.knowledge
            knowledge.load(from: document.agents.directory)
            try knowledge.writeSkill(named: arguments.string("name"), text: arguments.string("text"))
            return .bool(true)
        }
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
