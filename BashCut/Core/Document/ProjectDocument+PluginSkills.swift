import BashCutAgent
import BashCutAutomation
import BashCutPlugin
import Foundation

/// Plugin skills (#377): what ready plugins ship in `contributes.skills` reaches agents the way project and user
/// skills do. They are listed in the agents' knowledge with their paths, linked into the open project's
/// `.claude/skills` and `.agents/skills`, and given to plugin terminals; `skills list --scope plugin` shows them.
extension ProjectDocument {
    /// The ready plugins' skills changed (installed, trusted, enabled, disabled, removed or reloaded).
    func pluginSkillsChanged() {
        agents.knowledge.pluginSkills = plugins.skills
        agents.knowledge.refreshPluginSkills()
        syncPluginSkillLinks()
    }

    /// Links the plugin skills into the open project and removes the links of skills no plugin provides any more.
    func syncPluginSkillLinks() {
        agents.knowledge.pluginSkills = plugins.skills
        guard fileURL != nil else { return }
        do {
            let linked = try agents.knowledgeStore.syncPluginSkills(plugins.skills)
            DebugLog.write("plugin", "plugin skills linked in the project: \(linked.count)")
        } catch {
            DebugLog.write("plugin", "plugin skills not linked: \(error.localizedDescription)")
        }
    }
}
