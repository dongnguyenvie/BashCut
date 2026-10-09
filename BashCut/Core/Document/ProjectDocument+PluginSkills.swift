import BashCutAgent
import BashCutAutomation
import BashCutPlugin
import Foundation

/// Plugin skills (#377): what ready plugins ship in `contributes.skills` reaches agents the way project and user
/// skills do. They are listed in the agents' knowledge with their paths, linked into the user's agent folders (or
/// the open project's `.claude/skills` and `.agents/skills`), and given to plugin terminals; `skills list --scope
/// plugin` shows them.
extension ProjectDocument {
    /// The ready plugins' skills changed (installed, trusted, enabled, disabled, removed or reloaded).
    func pluginSkillsChanged() {
        agents.knowledge.pluginSkills = plugins.skills
        agents.knowledge.refreshPluginSkills()
        syncPluginSkillLinks()
    }

    /// Links the plugin skills into the user's agent folders, so `/` offers them before any project exists, and into
    /// the open project only when no user folder took them (no duplicates in `/`). Removes the links of skills no
    /// plugin provides any more.
    func syncPluginSkillLinks() {
        agents.knowledge.pluginSkills = plugins.skills
        let userFolders = AgentKnowledgeStore.userPluginSkillFolders(
            home: FileManager.default.homeDirectoryForCurrentUser, variables: ProcessInfo.processInfo.environment)
        do {
            let ledger = Self.libraryApplicationSupport.appendingPathComponent("BashCut/plugin-skills.json")
            let linked = try AgentKnowledgeStore.syncUserPluginSkills(plugins.skills, folders: userFolders, ledger: ledger)
            DebugLog.write("plugin", "plugin skills linked for the user: \(linked.count) in \(userFolders.count) folders")
        } catch {
            DebugLog.write("plugin", "plugin skills not linked for the user: \(error.localizedDescription)")
        }
        guard fileURL != nil else { return }
        do {
            let linked = try agents.knowledgeStore.syncPluginSkills(userFolders.isEmpty ? plugins.skills : [])
            DebugLog.write("plugin", "plugin skills linked in the project: \(linked.count)")
        } catch {
            DebugLog.write("plugin", "plugin skills not linked: \(error.localizedDescription)")
        }
    }
}
