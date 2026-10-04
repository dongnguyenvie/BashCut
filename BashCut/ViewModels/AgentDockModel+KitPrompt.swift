import BashCutAgent
import Foundation

/// The agent dock's banner asking to set up the agent kit for Claude Code and Codex outside BashCut. BashCut's own
/// tabs load the kit already; agents in the user's terminal only know BashCut once it is set up for them.
struct AgentKitPrompt: Equatable {
    let version: String
    let skills: Int
    /// The agents found on this Mac whose kit is missing or older than BashCut's.
    let targets: [AgentKitSetup.Target]
    /// Every target has the kit already, only an older one.
    let outdated: Bool

    init?(kit: AgentKit?, statuses: [AgentKitSetup.Target: AgentKitSetup.Status]) {
        guard let kit else { return nil }
        let targets = AgentKitSetup.Target.allCases.filter { target in
            guard let status = statuses[target], status.executable != nil else { return false }
            return !status.installed || status.outdated
        }
        guard !targets.isEmpty else { return nil }
        version = kit.version
        skills = kit.skills.count
        self.targets = targets
        outdated = targets.allSatisfy { statuses[$0]?.installed == true }
    }

    /// "Claude Code", "Codex" or "Claude Code and Codex".
    var agentNames: String {
        let names = targets.map { $0 == .claude ? "Claude Code" : "Codex" }
        return names.count == 2 ? String(format: String(localized: "%@ and %@"), names[0], names[1]) : names.joined()
    }
}

extension AgentDockModel {
    var showsKitPrompt: Bool {
        guard let kitPrompt else { return false }
        return settings.agentKitPromptDismissed != kitPrompt.version
    }

    /// Checks Claude Code and Codex again, at most every five minutes unless `force`; it runs their CLIs.
    func refreshKitPrompt(force: Bool = false) async {
        if !force, let checked = kitPromptChecked, Date().timeIntervalSince(checked) < 300 { return }
        kitPromptChecked = Date()
        let kit = try? document.installedAgentKit()
        kitPrompt = AgentKitPrompt(kit: kit, statuses: await document.agentSetupStatuses())
    }

    /// Settings › Agents checked the agents itself; reuse what it found.
    func updateKitPrompt(kit: AgentKit?, statuses: [AgentKitSetup.Target: AgentKitSetup.Status]) {
        kitPromptChecked = Date()
        kitPrompt = AgentKitPrompt(kit: kit, statuses: statuses)
    }

    /// The banner's Set Up: what `agent setup claude` and `agent setup codex` do, for each agent that needs it.
    func setUpKitFromPrompt() {
        guard let targets = kitPrompt?.targets, !kitSettingUp else { return }
        kitSettingUp = true
        Task {
            var done: [String] = []
            for target in targets {
                do { done.append(try await document.setUpAgent(target.rawValue, remove: false)) } catch {
                    done.append(error.localizedDescription)
                }
            }
            document.message = done.joined(separator: "; ")
            kitSettingUp = false
            await refreshKitPrompt(force: true)
        }
    }

    /// Later: hides the banner until BashCut has a newer kit.
    func dismissKitPrompt() {
        settings.agentKitPromptDismissed = kitPrompt?.version
    }
}
