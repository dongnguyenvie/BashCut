import BashCutAutomation
import BashCutEngine
import BashCutImport
import BashCutPlugin
import BashCutProject
import Foundation

/// Library tools and health checks shared by their panels and automation (agent knowledge: ProjectDocument+Knowledge).
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
        handle("fonts.list") { document, arguments, _ in
            let query = arguments.optionalString("query")?.lowercased()
            let language = arguments.optionalString("language") ?? document.contentLanguage
            let known = language.isEmpty ? nil : ProjectFonts.alphabet(language).map { _ in language }
            let covering = arguments.optionalBool("covers") ?? false
            if covering, known == nil {
                throw RPCFailure(-32602, language.isEmpty
                    ? "--covers needs a language: pass --language or set the project's content language"
                    : "Unknown language \(language)")
            }
            let fonts = ProjectFonts.list(
                projectRoot: document.fileURL?.deletingLastPathComponent(), installed: !(arguments.optionalBool("project") ?? false))
                .filter { font in
                    (!covering || font.covers(language) == true)
                        && query.map { font.postScriptName.lowercased().contains($0) || font.family.lowercased().contains($0) }
                            ?? true
                }
            return .array(fonts.map { $0.json(language: known) })
        }
        handle("fonts.import") { document, arguments, _ in
            let language = document.contentLanguage.isEmpty ? nil : document.contentLanguage
            return .array(try document.importFont(from: URL(fileURLWithPath: arguments.string("path"))).map { $0.json(language: language) })
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
        registerKnowledgeCommands()
    }

    /// Health checks run now (`plugins.list --health`): every plugin's, or one's.
    func pluginHealthJSON(_ id: String?) async throws -> JSONValue {
        plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent())
        var selected = plugins.plugins
        if let id {
            selected = selected.filter { $0.id == id }
            guard !selected.isEmpty else { throw RPCFailure(-32602, "Unknown plugin \(id)") }
        }
        var results: [JSONValue] = []
        for plugin in selected {
            results.append(Self.healthJSON(await plugins.checkHealthNow(plugin)))
        }
        return .array(results)
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
