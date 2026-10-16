import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation
import Observation
import SwiftTerm
import SwiftUI

private final class AgentDockWindowDelegate: NSObject, NSWindowDelegate {
    let closed: () -> Void
    init(closed: @escaping () -> Void) { self.closed = closed }
    func windowWillClose(_ notification: Notification) { closed() }
}

@MainActor @Observable final class AgentDockModel {
    unowned let document: ProjectDocument
    var sessions: [TerminalSession] = []
    var selectedSession: UUID? {
        didSet { if selectedSession != nil, selectedSession != oldValue { pluginViewKey = nil } }
    }
    /// The chat agent (plugin ID) whose tab is shown instead of a terminal.
    var chatPluginID: String? {
        didSet { if chatPluginID != nil { pluginViewKey = nil } }
    }
    /// The plugin view (`<plugin>/<view>`, plugin API 8 `location: dock`) whose tab is shown instead of a terminal or chat.
    var pluginViewKey: String?
    var sessionBookmarks = AgentSessionBookmarks()
    var sessionDiscoveryMessage = ""
    var settings: SettingsModel { document.settings }
    /// Whether the Knowledge window is open.
    private(set) var showKnowledge = false
    var error = ""
    let knowledge = AgentKnowledgeModel()
    let askModel = AgentAskModel()
    private let sessionStore = AgentSessionStore()
    /// Session transcripts live in the agents' configuration folders, which users may move.
    private var sessionDiscovery: AgentSessionDiscovery {
        let folders = document.currentAgentConfigFolders
        return AgentSessionDiscovery(roots: [
            .claude: folders.claude.url.appendingPathComponent("projects", isDirectory: true),
            .codex: folders.codex.url.appendingPathComponent("sessions", isDirectory: true),
        ])
    }
    private var sessionDiscoveryTask: Task<Void, Never>?
    /// BashCut's kit as last checked for the setup card; nil when there is none or it was not checked yet.
    var setupKit: AgentKit?
    var kitSettingUp = false
    @ObservationIgnored var kitPromptChecked: Date?
    /// What Claude Code and Codex reported last, and BashCut's kit version, for the setup card.
    var kitStatuses: [AgentKitSetup.Target: AgentKitSetup.Status] = [:]
    var kitVersion: String?
    /// Agent tabs started before the skills were installed: a running CLI loads them only when it restarts.
    var kitRestartSessions: [UUID] = []
    /// Whether the setup card shows its steps; it opens the first time a kit version is seen.
    var setupExpanded = false
    /// A step was started from the card in this session: once all are done it stays, ticked, until Done.
    var setupFinishedHere = false
    /// The folder question on show; answering resumes the launch waiting in `folderTrustAnswer`.
    var folderTrustPrompt: AgentFolderTrustPrompt?
    @ObservationIgnored var folderTrustAnswer: CheckedContinuation<AgentFolderTrustPrompt.Answer, Never>?
    /// Folders the user allowed since BashCut started (`<agent>:<folder>`, and `claude-bypass:<settings.json>` for
    /// Bypass Permissions mode), written again without asking when a running CLI saved its config over them.
    @ObservationIgnored var allowedFolders: Set<String> = []
    @ObservationIgnored private var detachedWindow: NSWindow? {
        didSet { document.ui.setAgentPoppedOut(detachedWindow != nil) }
    }
    @ObservationIgnored private var detachedDelegate: AgentDockWindowDelegate?
    @ObservationIgnored private var knowledgeWindow: NSWindow?
    @ObservationIgnored private var knowledgeDelegate: AgentDockWindowDelegate?

    init(document: ProjectDocument) {
        self.document = document
        // The model-API panel was removed; forget its saved connection (API keys stay in the user's Keychain).
        UserDefaults.standard.removeObject(forKey: "modelConfiguration")
    }
    var current: TerminalSession? { sessions.first { $0.id == selectedSession } }
    /// The agent chosen in Settings, or the one used last while Settings says "Last used".
    var defaultProvider: AgentProviderID {
        let raw = settings.defaultProviderRaw
        return AgentDefault.resolve(
            chosen: raw == SettingsModel.lastUsedAgent ? nil : AgentProviderID(rawValue: raw),
            last: settings.lastAgentRaw.map(AgentProviderID.init(rawValue:)), available: agentChoices.map(\.id))
    }
    var isDetached: Bool { detachedWindow != nil }
    var directory: URL {
        settings.workspace ?? document.fileURL?.deletingLastPathComponent() ?? settings.defaultProjectsFolder
    }
    /// Knowledge lives in the open project and the user's folder, not in the workspace (#100); the workspace and
    /// home folder are only searched for memos older builds left there.
    var knowledgeStore: AgentKnowledgeStore {
        AgentKnowledgeStore(
            project: document.fileURL?.deletingLastPathComponent(),
            user: AgentKnowledgeStore.userFolder(applicationSupport: ProjectDocument.libraryApplicationSupport),
            legacyFolders: [settings.workspace, FileManager.default.homeDirectoryForCurrentUser].compactMap { $0 })
    }
    /// Loads the knowledge, with the agent kit's skills shown read-only (found, not installed: that copies files).
    func loadKnowledge() {
        knowledge.load(knowledgeStore, kit: AgentKit.locate(folder: settings.agentKitFolder, support: StorageUsage.supportFolder))
    }

    /// Keeps the dock's Knowledge badge current: loads the open project's knowledge, then reloads when files change.
    func refreshKnowledgeBadge() async {
        guard knowledge.store?.project == knowledgeStore.project, knowledge.store != nil else { return loadKnowledge() }
        await knowledge.refreshIfChanged()
    }
    var toolsDirectory: String { Bundle.main.executableURL?.deletingLastPathComponent().path ?? "" }
    /// Whether starting this agent continues its last conversation for the project.
    func canContinue(_ provider: AgentProviderID) -> Bool { !sessionBookmarks[provider].isEmpty }

    /// Starts a new conversation: forgets the saved one so this and later launches do not resume it.
    func startNewConversation(_ provider: AgentProviderID) {
        sessionBookmarks[provider] = ""
        saveSessionBookmarks()
        open(provider)
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard let url = ModalCenter.shared.open(panel, name: "choose-workspace")?.first else { return }
        settings.workspace = url
        document.rebuild()
    }
    /// Turning the switch on, or asking for a new token, writes a fresh token file; off removes it.
    func applyExternalAgentPreference() {
        document.applyExternalAgentAccess(enabled: settings.allowExternalAgents)
    }
    func applyAgentEditPreference() {
        if !settings.agentsCanEdit {
            document.rejectScopeHold()
            document.chatAgents.revokeTokens()
            for session in sessions where session.provider.isAgent {
                document.registry.revoke(session.token)
            }
        }
    }
    func openDefault() { open(defaultProvider) }
    /// Opens a terminal tab: a built-in provider at once, a plugin's terminal after its plugin answers `launch`.
    func open(_ id: AgentProviderID) {
        guard let provider = AgentProviders.provider(id) else {
            Task {
                do { try await openPluginTerminal(id.rawValue) } catch { self.error = error.localizedDescription }
            }
            return
        }
        Task {
            do { try await startBuiltIn(provider) } catch { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    func startBuiltIn(_ provider: any AgentProvider) async throws -> TerminalSession {
        loadKnowledge()
        let canEdit = !provider.isAgent || settings.agentsCanEdit
        return try await start(
            provider, canEdit: canEdit, prompt: sessionPrompt(canEdit: canEdit), icon: Self.icon(for: provider.id))
    }

    /// BashCut's instructions and the project context, for a new terminal's system prompt.
    func sessionPrompt(canEdit: Bool) -> String {
        CommandCatalog.instructions
            + (canEdit ? "" : "\nTimeline edits are disabled in BashCut Settings for this session.")
            + "\n" + document.contextText() + "\n" + knowledge.context
    }

    /// Issues the tab's token, launches `provider` in a new tab and looks for its session to resume next time. Claude
    /// Code and Codex first get the user's leave to work in the folder they start in.
    @discardableResult
    func start(
        _ provider: any AgentProvider, canEdit: Bool, prompt: String, icon: String
    ) async throws -> TerminalSession {
        let token = canEdit ? document.registry.issueToken(author: provider.author) : ""
        do {
            let launchedAt = Date()
            let context = AgentSessionContext(
                project: document.fileURL, token: token, socket: AutomationPaths.socket,
                toolsDirectory: toolsDirectory, prompt: prompt)
            let launch = try AgentLaunch.make(
                provider: provider, workspace: directory, context: context,
                resumeID: resumeID(for: provider), kit: document.agentKitLaunch(), pluginSkills: document.agentPluginSkills(),
                onlyBashCutMCP: document.settings.agentOnlyBashCutMCP,
                environment: document.currentAgentEnvironment)
            try await ensureFolderTrust(provider, folder: URL(fileURLWithPath: launch.directory, isDirectory: true))
            let session = TerminalSession(provider: provider, token: token, launch: launch, icon: icon)
            sessions.append(session)
            selectedSession = session.id
            chatPluginID = nil
            error = ""
            if provider.isAgent {
                settings.lastAgentRaw = provider.id.rawValue
                if resumeID(for: provider).isEmpty {
                    discoverLaunchedSession(
                        provider: provider, workspace: URL(fileURLWithPath: launch.directory),
                        session: session.id, launchedAt: launchedAt)
                } else {
                    saveSessionBookmarks()
                }
            }
            return session
        } catch {
            document.registry.revoke(token)
            throw error
        }
    }

    static func icon(for provider: AgentProviderID) -> String {
        switch provider {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        default: "terminal"
        }
    }
    /// Bookmarks of the agents with an open tab, taken before the project switches so the new project continues
    /// the same conversations.
    func liveBookmarks() -> [AgentProviderID: String] {
        var live: [AgentProviderID: String] = [:]
        for session in sessions where session.provider.isAgent {
            let id = sessionBookmarks[session.provider.id]
            if !id.isEmpty { live[session.provider.id] = id }
        }
        return live
    }

    /// Tabs stay open across a project switch (an agent that creates or opens a project keeps working). Their
    /// tokens must read the new project before editing (`CommandRegistry.projectSwitched`), their conversations are
    /// bookmarked for the new project too, and the ones not found yet are looked for again.
    func keepSessions(after switching: [AgentProviderID: String]) {
        guard !sessions.isEmpty, let project = document.fileURL else { return }
        for (provider, id) in switching { sessionBookmarks[provider] = id }
        if !switching.isEmpty { saveSessionBookmarks() }
        for session in sessions where session.provider.isAgent && switching[session.provider.id] == nil {
            discoverLaunchedSession(
                provider: session.provider, workspace: directory, session: session.id,
                launchedAt: session.launchedAt)
        }
        let name = document.project.name
        sessionDiscoveryMessage = String(
            format: String(localized: "Terminals kept: they now work on %@ and read it before their next edit"), name)
        DebugLog.write("agents", "kept \(sessions.count) terminal(s) across the switch to \(project.path)")
    }

    func projectChanged() {
        sessionDiscoveryTask?.cancel()
        sessionDiscoveryMessage = ""
        sessionBookmarks = AgentSessionBookmarks()
        guard let project = document.fileURL else { return }
        do {
            sessionBookmarks = try sessionStore.load(project: project)
            error = ""
            discoverExistingSessions()
        } catch { self.error = error.localizedDescription }
    }
    func saveSessionBookmarks() {
        guard let project = document.fileURL else { return }
        do {
            try sessionStore.save(sessionBookmarks, project: project)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
    func handoff(to provider: AgentProviderID) {
        guard terminalChoices.contains(where: { $0.id == provider && $0.isAgent }) else { return }
        let source = current?.provider.title ?? "BashCut"
        loadKnowledge()
        let handoff =
            "Continue this editing task handed off from \(source).\n"
                + document.contextText() + "\n" + TimelineSummary.text(document.project) + "\n" + knowledge.context
        if let target = sessions.last(where: { $0.provider.id == provider }) {
            selectedSession = target.id
            chatPluginID = nil
            target.paste(handoff)
            return
        }
        Task {
            do {
                if let builtIn = AgentProviders.provider(provider) { try await startBuiltIn(builtIn) } else {
                    try await openPluginTerminal(provider.rawValue)
                }
            } catch {
                self.error = error.localizedDescription
                return
            }
            guard let target = sessions.last(where: { $0.provider.id == provider }),
                await target.waitUntilReady() == .ready, sessions.contains(where: { $0.id == target.id })
            else { return }
            target.paste(handoff)
        }
    }
    /// Shows a chat agent's tab and asks its plugin whether it is ready.
    func openChat(_ pluginID: String) {
        chatPluginID = pluginID
        let agent = document.chatAgents.model(for: pluginID)
        Task { await agent.refreshStatus() }
    }
    func close(_ session: TerminalSession) {
        document.rejectScopeHold(from: session.token)
        session.close()
        document.registry.revoke(session.token)
        sessions.removeAll { $0.id == session.id }
        if selectedSession == session.id { selectedSession = sessions.last?.id }
    }
    /// Ends what belongs to the open project: pending session lookups.
    func resetProjectState() {
        sessionDiscoveryTask?.cancel()
        closeKnowledge()
    }

    func closeAll() {
        if isDetached { attach() }
        resolveFolderTrust(.notNow)
        resetProjectState()
        for session in sessions {
            session.close()
            document.registry.revoke(session.token)
        }
        sessions.removeAll()
        selectedSession = nil
    }
    func resumeID(for provider: any AgentProvider) -> String {
        provider.isAgent ? sessionBookmarks[provider.id].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

extension AgentDockModel {
    fileprivate func discoverExistingSessions() {
        guard let project = document.fileURL else { return }
        let workspace = directory
        let documentSession = document.sessionID
        let discovery = sessionDiscovery
        let plugins = terminalPlugins
        sessionDiscoveryTask = Task {
            let started = Date()
            let reads = AgentSessionDiscovery.Cache.shared.reads
            let scan = Task.detached(priority: .utility) {
                AgentProviders.agents.compactMap { provider in
                    discovery.latest(provider: provider, project: project, workspace: workspace)
                        .map { (provider: provider.id, title: provider.title, id: $0) }
                }
            }
            // Closing or switching the project cancels this task; the scan stops with it.
            var found = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            DebugLog.write(
                "agents", "session scan read \(AgentSessionDiscovery.Cache.shared.reads - reads) file(s) in "
                    + "\(Int(Date().timeIntervalSince(started) * 1000)) ms")
            for plugin in plugins {
                if let id = await pluginSession(plugin, project: project, workspace: workspace, notBefore: nil) {
                    found.append((AgentProviderID(rawValue: plugin.id), plugin.manifest.displayName, id))
                }
            }
            guard !Task.isCancelled, document.sessionID == documentSession else { return }
            var names: [String] = []
            for match in found where sessionBookmarks[match.provider].isEmpty {
                sessionBookmarks[match.provider] = match.id
                names.append(match.title)
            }
            guard !names.isEmpty else { return }
            saveSessionBookmarks()
            sessionDiscoveryMessage = String(
                format: String(localized: "You can continue your last %@ conversation"),
                names.joined(separator: " / "))
        }
    }

    fileprivate func discoverLaunchedSession(
        provider: any AgentProvider, workspace: URL, session: UUID, launchedAt: Date
    ) {
        guard let project = document.fileURL else { return }
        let documentSession = document.sessionID
        let discovery = sessionDiscovery
        Task {
            for delay in [300, 700, 1_500, 3_000] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                let identifier: String?
                if let plugin = terminalPlugins.first(where: { $0.id == provider.id.rawValue }) {
                    identifier = await pluginSession(
                        plugin, project: project, workspace: directory, notBefore: launchedAt)
                } else {
                    identifier = await Task.detached(priority: .utility) {
                        discovery.latest(
                            provider: provider, project: project, workspace: workspace,
                            notBefore: launchedAt)
                    }.value
                }
                guard document.sessionID == documentSession,
                    sessions.contains(where: { $0.id == session })
                else { return }
                guard let identifier else { continue }
                guard sessionBookmarks[provider.id].isEmpty else { return }
                sessionBookmarks[provider.id] = identifier
                saveSessionBookmarks()
                sessionDiscoveryMessage = String(
                    format: String(localized: "%@ will continue this conversation next time"), provider.title)
                return
            }
        }
    }

    func detach() {
        if let detachedWindow {
            detachedWindow.makeKeyAndOrderFront(nil)
            return
        }
        document.ui.showAgentDock = false
        let window = AuxiliaryWindow.make(
            title: String(localized: "BashCut Agent"), size: NSSize(width: 480, height: 760),
            minSize: NSSize(width: 360, height: 520), content: AgentDockView(model: self, detached: true))
        let delegate = AgentDockWindowDelegate { [weak self] in
            self?.detachedWindow = nil
            self?.detachedDelegate = nil
            self?.document.ui.showAgentDock = true
        }
        detachedDelegate = delegate
        window.delegate = delegate
        detachedWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens the Knowledge window (#68): what agents learned, the memos and the project skills. It is a window, not a
    /// sheet, so the user can keep it open while agents work; it reloads when the files change.
    func openKnowledge() {
        loadKnowledge()
        if let knowledgeWindow {
            knowledgeWindow.makeKeyAndOrderFront(nil)
            return
        }
        knowledge.beginVisit()
        knowledge.askAgent = { [weak self] request in self?.ask(request) ?? false }
        let window = AuxiliaryWindow.make(
            title: String(localized: "Knowledge"), size: NSSize(width: 1060, height: 720),
            minSize: NSSize(width: 860, height: 540), content: KnowledgeManagerView(model: knowledge, ui: document.ui))
        let delegate = AgentDockWindowDelegate { [weak self] in
            self?.knowledge.endVisit()
            self?.knowledgeWindow = nil
            self?.knowledgeDelegate = nil
            self?.showKnowledge = false
        }
        knowledgeDelegate = delegate
        window.delegate = delegate
        knowledgeWindow = window
        showKnowledge = true
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func closeKnowledge() {
        knowledgeWindow?.close()
    }

    func attach() {
        guard let window = detachedWindow else {
            document.ui.showAgentDock = true
            return
        }
        detachedWindow = nil
        detachedDelegate = nil
        window.delegate = nil
        window.close()
        document.ui.showAgentDock = true
    }
}
