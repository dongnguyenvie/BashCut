import BashCutAgent
import BashCutPlugins
import BashCutProject
import Foundation

/// The Claude Code and Codex CLIs on this Mac that still need the agent kit (the setup card's step ①). BashCut's own
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

}

extension AgentDockModel {
    /// The registry bundle the setup card's Editing tools step installs (`bundles.json`).
    static let starterBundle = "starter"

    /// The setup card's two steps as this Mac has them.
    var setupChecklist: AgentSetupChecklist {
        AgentSetupChecklist(
            skills: AgentSetupChecklist.skills(kitVersion: kitVersion, statuses: setupStatuses),
            tools: AgentSetupChecklist.tools(starterPlugins))
    }

    /// The starter bundle's default plugins, or nil when the registry (or the bundle) is not known.
    private var starterPlugins: [AgentSetupChecklist.ToolPlugin]? {
        let plugins = document.plugins
        guard PluginChannel.current.allowsUserPlugins, let bundle = plugins.registry?.bundle(Self.starterBundle)
        else { return nil }
        return bundle.plugins.filter(\.checkedByDefault).map { member in
            guard let plugin = plugins.plugin(member.id) else { return .init(installed: false, healthy: false) }
            if plugin.manifest.dependencies.isEmpty { return .init(installed: true, healthy: true) }
            return .init(installed: true, healthy: plugins.health[plugin.id].map { $0.state == .ready })
        }
    }

    /// Download and disk size of the starter bundle's default plugins not installed yet; 0 when the registry does
    /// not say.
    var starterBytes: Int64 {
        guard let bundle = document.plugins.registry?.bundle(Self.starterBundle) else { return 0 }
        return document.plugins.members(of: bundle).filter { $0.member.checkedByDefault && $0.installable }
            .reduce(Int64(0)) { total, member in
                total + Int64((member.listing?.version?.size ?? 0) + (member.listing?.version?.downloadBytes ?? 0))
            }
    }

    /// What Claude Code and Codex reported, narrowed to the agent the user picked: the shown tab's agent, else the
    /// dock's default (Settings, or the last used). Both when the pick is neither or its CLI is not on this Mac.
    var setupStatuses: [AgentKitSetup.Target: AgentKitSetup.Status] {
        AgentSetupChecklist.statuses(kitStatuses, pickedFrom: [current?.provider.id, defaultProvider].compactMap { $0 })
    }

    /// The agents the card's step ① sets up; nil when none needs it or they were not checked yet.
    var kitPrompt: AgentKitPrompt? { AgentKitPrompt(kit: setupKit, statuses: setupStatuses) }

    /// "Claude Code", "Codex" or "Claude Code and Codex": the agents the card sets up.
    var setupAgentNames: String {
        let found = AgentKitSetup.Target.allCases.filter { setupStatuses[$0]?.executable != nil }
        let names = (found.isEmpty ? [.claude] : found).map { $0 == .claude ? "Claude Code" : "Codex" }
        return names.count == 2 ? String(format: String(localized: "%@ and %@"), names[0], names[1]) : names.joined()
    }

    /// Later folded the card into the dock header's Setup chip (until BashCut has a newer kit).
    var setupFolded: Bool {
        settings.agentKitPromptDismissed == AgentSetupChecklist.foldKey(kitVersion: kitVersion)
    }

    /// Something is left: a step, or a tab to restart so it loads the skills just installed.
    var setupPending: Bool { !setupChecklist.isComplete || !restartSessions.isEmpty }

    /// The full card is on show (not folded into the chip). After its last step is done from the card, it stays
    /// with every step ticked until Done.
    var showsSetupCard: Bool { (setupPending && !setupFolded) || setupFinishedHere }

    /// The open agent tabs that started before the skills were installed.
    var restartSessions: [TerminalSession] {
        sessions.filter { kitRestartSessions.contains($0.id) }
    }

    /// Checks Claude Code and Codex again, at most every five minutes unless `force`; it runs their CLIs. Also
    /// reads the saved plugin registry for the starter bundle and checks its plugins' health once.
    func refreshKitPrompt(force: Bool = false) async {
        await refreshStarterBundle()
        if !force, let checked = kitPromptChecked, Date().timeIntervalSince(checked) < 300 { return }
        kitPromptChecked = Date()
        let kit = try? document.installedAgentKit()
        updateKitPrompt(kit: kit, statuses: await document.agentSetupStatuses(fresh: force))
    }

    /// Settings › Agents checked the agents itself; reuse what it found.
    func updateKitPrompt(kit: AgentKit?, statuses: [AgentKitSetup.Target: AgentKitSetup.Status]) {
        kitPromptChecked = Date()
        let firstLook = kitVersion == nil && settings.agentKitPromptSeen != kit?.version
        kitVersion = kit?.version
        kitStatuses = statuses
        setupKit = kit
        // The card opens the first time a kit version is seen with a step left.
        if firstLook, setupPending, let version = kit?.version {
            setupExpanded = true
            settings.agentKitPromptSeen = version
        }
    }

    /// The saved registry names the bundle without fetching; its plugins' dependencies are probed once.
    private func refreshStarterBundle() async {
        let plugins = document.plugins
        guard PluginChannel.current.allowsUserPlugins else { return }
        await plugins.loadCachedRegistry()
        if plugins.registry == nil { await plugins.refreshRegistry() }
        guard let bundle = plugins.registry?.bundle(Self.starterBundle) else { return }
        for member in bundle.plugins where member.checkedByDefault {
            guard let plugin = plugins.plugin(member.id), plugins.health[plugin.id] == nil,
                !plugin.manifest.dependencies.isEmpty
            else { continue }
            await plugins.checkHealthNow(plugin)
        }
    }

    /// Step ①'s Install skills / Update: what `agent setup claude` and `agent setup codex` do, for each agent that
    /// needs it. Agent tabs already running are offered a restart.
    func setUpKitFromPrompt() {
        guard let targets = kitPrompt?.targets, !kitSettingUp else { return }
        kitSettingUp = true
        let running = sessions.filter { session in
            targets.contains { $0.rawValue == session.provider.id.rawValue }
        }.map(\.id)
        Task {
            var done: [String] = []
            var installed = false
            for target in targets {
                do {
                    done.append(try await document.setUpAgent(target.rawValue, remove: false))
                    installed = true
                } catch {
                    done.append(error.localizedDescription)
                }
            }
            document.message = done.joined(separator: "; ")
            if installed { kitRestartSessions = (kitRestartSessions + running).filter { id in sessions.contains { $0.id == id } } }
            setupFinishedHere = true
            // Still "Installing…" while the CLIs are checked again, so the button does not come back meanwhile. Only
            // the CLIs: the starter bundle's registry and plugin health have nothing to do with the skills.
            kitPromptChecked = Date()
            updateKitPrompt(kit: try? document.installedAgentKit(), statuses: await document.agentSetupStatuses(fresh: true))
            kitSettingUp = false
        }
    }

    /// Step ②'s Install…: Plugins › Browse with the starter bundle's approval (one sheet, each plugin checked by
    /// its default). The button form of `/bc:setup`, without the agent.
    func installStarterTools() {
        setupFinishedHere = true
        document.plugins.tab = .browse
        document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
        document.ui.showPlugins = true
        Task {
            do { try await document.plugins.requestBundle(Self.starterBundle) } catch {
                document.plugins.message = error.localizedDescription
            }
        }
    }

    /// Closes an agent tab that started before the skills were installed and starts it again, continuing the same
    /// conversation (its resume bookmark), so the CLI loads the new skills.
    func restartForKit(_ session: TerminalSession) {
        kitRestartSessions.removeAll { $0 == session.id }
        guard let provider = AgentProviders.provider(session.provider.id) else { return }
        close(session)
        Task {
            do { try await startBuiltIn(provider) } catch { self.error = error.localizedDescription }
        }
    }

    /// `agent.restart-tab`: restarts every tab waiting for the new skills.
    func restartTabsForKit() {
        restartSessions.forEach(restartForKit)
    }

    /// Later: folds the card into the dock header's Setup chip until BashCut has a newer kit.
    func dismissKitPrompt() {
        settings.agentKitPromptDismissed = AgentSetupChecklist.foldKey(kitVersion: kitVersion)
    }

    /// The setup card as `ui view` reports it: steps done, folded into the chip, tabs waiting for a restart.
    var setupJSON: JSONValue {
        let checklist = setupChecklist
        return .object([
            "done": .integer(checklist.done), "total": .integer(checklist.total),
            "skills": .string(checklist.skillsName), "tools": .string(checklist.toolsName),
            "kitVersion": kitVersion.map(JSONValue.string) ?? .null,
            "agents": .string(setupAgentNames),
            "card": .string(
                !showsSetupCard ? (setupPending ? "chip" : "hidden") : setupExpanded ? "open" : "collapsed"),
            "restartTabs": .array(restartSessions.map { .string($0.title) }),
        ])
    }

    /// Step ②'s Finish setup…: Plugins › Installed, where a plugin's Install Dependencies… waits.
    func showStarterSetup() {
        document.plugins.tab = .installed
        document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
        document.ui.showPlugins = true
    }

    /// Done on the finished card: hides it.
    func closeFinishedSetup() { setupFinishedHere = false }

    /// The Setup chip: unfolds the card with its steps open.
    func showSetupCard() {
        settings.agentKitPromptDismissed = nil
        setupExpanded = true
    }
}
