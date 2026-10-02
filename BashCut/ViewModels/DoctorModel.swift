import BashCutAutomation
import BashCutPlugin
import Foundation
import Observation

struct DoctorCheck: Identifiable, Sendable {
    enum State: Int, Sendable { case pass, warning, fail }
    let id: String
    let title: String
    let detail: String
    let state: State
}

@MainActor @Observable final class DoctorModel {
    var checks: [DoctorCheck] = []
    var running = false
    private var runID = UUID()
    private let pluginRunner = PluginProcessRunner(timeout: 15, maximumOutputBytes: 256 * 1024)

    var summary: DoctorCheck.State {
        checks.map(\.state).max(by: { $0.rawValue < $1.rawValue }) ?? .warning
    }

    func run(
        workspace: URL, projectRoot: URL?, toolsDirectory: String,
        plugins: [InstalledPlugin], pluginDiagnostics: [String]
    ) {
        let id = UUID()
        runID = id
        running = true
        checks = Self.localChecks(
            workspace: workspace, projectRoot: projectRoot, toolsDirectory: toolsDirectory,
            pluginCount: plugins.count, pluginDiagnostics: pluginDiagnostics)
        Task {
            let runner = pluginRunner
            let results = await withTaskGroup(
                of: PluginHealth.self, returning: [PluginHealth].self
            ) { group in
                for plugin in plugins { group.addTask { await runner.health(plugin: plugin) } }
                var values: [PluginHealth] = []
                for await value in group { values.append(value) }
                return values
            }
            guard runID == id else { return }
            for result in results.sorted(by: { $0.pluginID < $1.pluginID }) {
                let missing = result.dependencies.filter { $0.state != .available }
                checks.append(
                    DoctorCheck(
                        id: "plugin." + result.pluginID, title: "Plugin " + result.pluginID,
                        detail: missing.isEmpty
                            ? "Ready"
                            : missing.map { "\($0.name): \($0.detail)" }.joined(separator: "\n"),
                        state: missing.isEmpty ? .pass : .warning))
            }
            running = false
        }
    }

    private static func localChecks(
        workspace: URL, projectRoot: URL?, toolsDirectory: String,
        pluginCount: Int, pluginDiagnostics: [String]
    ) -> [DoctorCheck] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let workspaceExists = manager.fileExists(atPath: workspace.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        var values = [
            DoctorCheck(
                id: "workspace", title: "Workspace",
                detail: workspaceExists ? workspace.path : "Folder is missing: " + workspace.path,
                state: workspaceExists && manager.isReadableFile(atPath: workspace.path)
                    && manager.isWritableFile(atPath: workspace.path) ? .pass : .fail),
            executableCheck("claude", required: true, toolsDirectory: toolsDirectory),
            executableCheck("codex", required: true, toolsDirectory: toolsDirectory),
            executableCheck("python3", required: false, toolsDirectory: toolsDirectory),
            executableCheck("ffmpeg", required: false, toolsDirectory: toolsDirectory),
            DoctorCheck(
                id: "automation", title: "Automation socket",
                detail: manager.fileExists(atPath: AutomationPaths.socket)
                    ? AutomationPaths.socket : "The local automation server is unavailable",
                state: manager.fileExists(atPath: AutomationPaths.socket) ? .pass : .fail),
        ]
        let hasInstructions = manager.fileExists(atPath: workspace.appendingPathComponent("CLAUDE.md").path)
            || manager.fileExists(atPath: workspace.appendingPathComponent("AGENTS.md").path)
        values.append(
            DoctorCheck(
                id: "instructions", title: "Agent instructions",
                detail: hasInstructions ? "CLAUDE.md or AGENTS.md found" : "Add CLAUDE.md or AGENTS.md",
                state: hasInstructions ? .pass : .warning))
        let hasSkills = manager.fileExists(atPath: workspace.appendingPathComponent(".claude/skills").path)
            || manager.fileExists(atPath: workspace.appendingPathComponent(".agents/skills").path)
        values.append(
            DoctorCheck(
                id: "skills", title: "Agent skills",
                detail: hasSkills ? "Skills folder found" : "No project skills folder found",
                state: hasSkills ? .pass : .warning))
        if let projectRoot {
            let folders = ["media", "voiceover", "subtitles", "render", ".bashcut"]
            let missing = folders.filter {
                !manager.fileExists(atPath: projectRoot.appendingPathComponent($0).path)
            }
            values.append(
                DoctorCheck(
                    id: "project", title: "Project folders",
                    detail: missing.isEmpty ? projectRoot.path : "Missing: " + missing.joined(separator: ", "),
                    state: missing.isEmpty ? .pass : .warning))
        } else {
            values.append(
                DoctorCheck(
                    id: "project", title: "Project", detail: "No saved project is open", state: .warning))
        }
        values.append(
            DoctorCheck(
                id: "catalog", title: "Plugin catalog",
                detail: pluginDiagnostics.isEmpty
                    ? "\(pluginCount) plugin(s) discovered" : pluginDiagnostics.joined(separator: "\n"),
                state: pluginDiagnostics.isEmpty ? .pass : .warning))
        return values
    }

    private static func executableCheck(
        _ name: String, required: Bool, toolsDirectory: String
    ) -> DoctorCheck {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            toolsDirectory, "/usr/local/bin", "/opt/homebrew/bin", home + "/.local/bin",
            home + "/.cargo/bin",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let path = paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first(where: FileManager.default.isExecutableFile(atPath:))
        return DoctorCheck(
            id: "executable." + name, title: name,
            detail: path ?? (required ? "Required command is not on PATH" : "Optional command is not on PATH"),
            state: path == nil ? (required ? .fail : .warning) : .pass)
    }
}
