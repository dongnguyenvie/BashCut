import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// A terminal the dock can open: a built-in provider or a plugin with `agent.terminal`.
struct TerminalChoice: Identifiable, Equatable {
    let id: AgentProviderID
    let title: String
    let icon: String
    /// AI agents get session bookmarks and handoff; a plain shell does not.
    let isAgent: Bool
    /// The plugin that adds it, nil for built-in ones.
    let pluginID: String?
}

/// Terminal agents from plugins (docs/specs/12-terminal-agents.md). The plugin answers `launch` with a command line;
/// the dock then starts it like Claude Code and Codex, with its own token.
extension AgentDockModel {
    /// Ready plugins that provide `agent.terminal`, in catalog order.
    var terminalPlugins: [InstalledPlugin] {
        document.plugins.plugins.filter { plugin in
            document.plugins.availability[plugin.id] == .ready
                && plugin.manifest.terminal != nil
                && (plugin.manifest.providers ?? []).contains { $0.capability == PluginAPI.agentTerminal }
        }
    }

    /// Built-in terminals first, then the plugins' ones.
    var terminalChoices: [TerminalChoice] {
        AgentProviders.all.map {
            TerminalChoice(id: $0.id, title: $0.title, icon: Self.icon(for: $0.id), isAgent: $0.isAgent, pluginID: nil)
        } + terminalPlugins.map {
            TerminalChoice(
                id: AgentProviderID(rawValue: $0.id), title: $0.manifest.displayName,
                icon: $0.manifest.terminal?.symbol ?? "terminal", isAgent: true, pluginID: $0.id)
        }
    }

    var agentChoices: [TerminalChoice] { terminalChoices.filter(\.isAgent) }

    /// Asks the plugin how to start its CLI, links the kit's skills where it wants them, and opens the tab.
    @discardableResult
    func openPluginTerminal(_ pluginID: String) async throws -> TerminalSession {
        guard let plugin = terminalPlugins.first(where: { $0.id == pluginID }) else {
            throw ProjectError.invalid("\(pluginID) is not a ready terminal agent (plugins list)")
        }
        loadKnowledge()
        let canEdit = settings.allowAgentEdits
        let prompt = sessionPrompt(canEdit: canEdit)
        let kit = document.agentKitLaunch()?.kit
        let folder = PluginTerminals.agentFolder(support: StorageUsage.supportFolder, pluginID: pluginID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let resume = sessionBookmarks[AgentProviderID(rawValue: pluginID)].trimmingCharacters(in: .whitespacesAndNewlines)
        let params = PluginTerminals.launchParams(
            workspace: directory, agentFolder: folder, project: document.fileURL, prompt: prompt,
            mcpExecutable: URL(fileURLWithPath: toolsDirectory).appendingPathComponent("bashcut-mcp").path,
            kit: kit, resume: resume, canEdit: canEdit)
        let result = try await document.plugins.service.terminal(params, using: try await resolveTerminal(plugin))
        let launch = try PluginTerminalLaunch(result: result, pluginDirectory: plugin.directory, agentFolder: folder)
        if let skills = launch.skillsFolder { try AgentKitInstall.syncSkills(of: kit, into: skills) }
        DebugLog.write("agents", "\(pluginID) terminal: \(launch.executable) with \(launch.arguments.count) argument(s)")
        return try start(
            PluginTerminalProvider(plugin: plugin, launch: launch), canEdit: canEdit, prompt: prompt,
            icon: plugin.manifest.terminal?.symbol ?? "terminal")
    }

    /// The plugin's newest session for the project (op `session`); nil when it has none or does not resume.
    func pluginSession(_ plugin: InstalledPlugin, project: URL, workspace: URL, notBefore: Date?) async -> String? {
        let folder = PluginTerminals.agentFolder(support: StorageUsage.supportFolder, pluginID: plugin.id)
        let params = PluginTerminals.sessionParams(
            workspace: workspace, agentFolder: folder, project: project, notBefore: notBefore)
        do {
            let result = try await document.plugins.service.terminal(params, using: try await resolveTerminal(plugin))
            return PluginTerminals.sessionID(from: result)
        } catch {
            DebugLog.write("agents", "\(plugin.id) session lookup: \(error.localizedDescription)")
            return nil
        }
    }

    private func resolveTerminal(_ plugin: InstalledPlugin) async throws -> ResolvedPluginProvider {
        let provider = plugin.manifest.providers?.first { $0.capability == PluginAPI.agentTerminal }
        return try await document.plugins.service.resolve(
            PluginAPI.agentTerminal, preferredProvider: provider?.id,
            projectRoot: document.fileURL?.deletingLastPathComponent())
    }
}
