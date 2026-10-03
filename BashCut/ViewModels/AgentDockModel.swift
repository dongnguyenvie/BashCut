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

@MainActor @Observable final class TerminalSession: Identifiable {
    let id = UUID()
    let provider: any AgentProvider
    let token: String
    let view = LocalProcessTerminalView(frame: .zero)
    var title: String
    init(provider: any AgentProvider, token: String, launch: AgentLaunch) {
        self.provider = provider
        self.token = token
        title = provider.title
        view.menu = EditMenus.terminalContextMenu(for: view)
        view.startProcess(
            executable: launch.executable, args: launch.arguments,
            environment: launch.environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: launch.directory)
    }
    func paste(_ text: String) {
        // Bracketed paste prevents multiline context from becoming immediate shell commands.
        let safe = text.replacingOccurrences(of: "\u{1b}", with: "")
        view.send(source: view, data: Array(("\u{1b}[200~" + safe + "\u{1b}[201~").utf8)[...])
    }
    func runCommand(_ text: String) { view.send(source: view, data: Array((text + "\n").utf8)[...]) }
    func close() {
        view.send(source: view, data: [3][...])
        view.terminate()
    }
}

@MainActor @Observable final class AgentDockModel {
    unowned let document: ProjectDocument
    var sessions: [TerminalSession] = []
    var selectedSession: UUID?
    var apiVisible = false
    var configuration = ModelConfiguration()
    var apiKey = ""
    var prompt = ""
    var output = ""
    var generating = false
    var includeContext = true
    var contextImageURL: URL?
    var mode = "script"
    var scriptLanguage = "python"
    var sessionBookmarks = AgentSessionBookmarks()
    var sessionDiscoveryMessage = ""
    var settings: SettingsModel { document.settings }
    var showKnowledge = false
    var error = ""
    let knowledge = AgentKnowledgeModel()
    var requestRevision: Int?
    var outputMode: String?
    var outputLanguage = "python"
    var generationID: UUID?
    let credentials = CredentialStore()
    let client = ModelClient()
    private let sessionStore = AgentSessionStore()
    private let sessionDiscovery = AgentSessionDiscovery()
    var generation: Task<Void, Never>?
    private var sessionDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var detachedWindow: NSWindow?
    @ObservationIgnored private var detachedDelegate: AgentDockWindowDelegate?

    init(document: ProjectDocument) {
        self.document = document
        if let data = UserDefaults.standard.data(forKey: "modelConfiguration"),
            let saved = try? JSONDecoder().decode(ModelConfiguration.self, from: data)
        {
            configuration = saved
        }
    }
    var current: TerminalSession? { sessions.first { $0.id == selectedSession } }
    var defaultProvider: AgentProviderID {
        let id = AgentProviderID(rawValue: settings.defaultProviderRaw)
        return AgentProviders.provider(id) == nil ? .codex : id
    }
    var isDetached: Bool { detachedWindow != nil }
    var directory: URL {
        settings.workspace ?? document.fileURL?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
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
        if !settings.allowAgentEdits {
            for session in sessions where session.provider.isAgent {
                document.registry.revoke(session.token)
            }
        }
    }
    func openDefault() { open(defaultProvider) }
    func open(_ id: AgentProviderID) {
        guard let provider = AgentProviders.provider(id) else { return }
        knowledge.load(from: directory)
        let canEdit = !provider.isAgent || settings.allowAgentEdits
        let token = canEdit ? document.registry.issueToken(author: provider.author) : ""
        do {
            let launchedAt = Date()
            let context = AgentSessionContext(
                project: document.fileURL, token: token, socket: AutomationPaths.socket,
                toolsDirectory: toolsDirectory,
                prompt: CommandCatalog.instructions
                    + (canEdit ? "" : "\nTimeline edits are disabled in BashCut Settings for this session.")
                    + "\n" + document.contextText() + "\n" + knowledge.context)
            let launch = try AgentLaunch.make(
                provider: provider, workspace: directory, context: context,
                resumeID: resumeID(for: provider))
            let session = TerminalSession(provider: provider, token: token, launch: launch)
            sessions.append(session)
            selectedSession = session.id
            apiVisible = false
            error = ""
            if provider.isAgent {
                if resumeID(for: provider).isEmpty {
                    discoverLaunchedSession(
                        provider: provider, workspace: URL(fileURLWithPath: launch.directory),
                        session: session.id, launchedAt: launchedAt)
                } else {
                    saveSessionBookmarks()
                }
            }
        } catch {
            document.registry.revoke(token)
            self.error = error.localizedDescription
        }
    }
    func projectChanged() {
        sessionDiscoveryTask?.cancel()
        sessionDiscoveryMessage = ""
        contextImageURL = nil
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
        guard AgentProviders.provider(provider)?.isAgent == true else { return }
        let source = current?.provider.title ?? "BashCut"
        let launchesTarget = !sessions.contains(where: { $0.provider.id == provider })
        if launchesTarget { open(provider) }
        guard let target = sessions.last(where: { $0.provider.id == provider }) else { return }
        selectedSession = target.id
        apiVisible = false
        knowledge.load(from: directory)
        let handoff =
            "Continue this editing task handed off from \(source).\n"
                + document.contextText() + "\n" + TimelineSummary.text(document.project) + "\n" + knowledge.context
        if launchesTarget {
            Task {
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                guard sessions.contains(where: { $0.id == target.id }) else { return }
                target.paste(handoff)
            }
        } else {
            target.paste(handoff)
        }
    }
    func close(_ session: TerminalSession) {
        session.close()
        document.registry.revoke(session.token)
        sessions.removeAll { $0.id == session.id }
        if selectedSession == session.id { selectedSession = sessions.last?.id }
    }
    func closeAll() {
        if isDetached { attach() }
        sessionDiscoveryTask?.cancel()
        cancel()
        requestRevision = nil
        outputMode = nil
        output = ""
        for session in sessions {
            session.close()
            document.registry.revoke(session.token)
        }
        sessions.removeAll()
        selectedSession = nil
    }
    private func resumeID(for provider: any AgentProvider) -> String {
        provider.isAgent ? sessionBookmarks[provider.id].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
    func sendContext(_ request: String = "", imageURL: URL? = nil) {
        knowledge.load(from: directory)
        var text = document.contextText() + "\n" + knowledge.context + "\n" + request
        contextImageURL = imageURL
        if let imageURL {
            text += "\nCurrent viewer frame: " + imageURL.path
        }
        if apiVisible { prompt = text } else { current?.paste(text) }
    }
}

extension AgentDockModel {
    fileprivate func discoverExistingSessions() {
        guard let project = document.fileURL else { return }
        let workspace = directory
        let documentSession = document.sessionID
        let discovery = sessionDiscovery
        sessionDiscoveryTask = Task {
            let found = await Task.detached(priority: .utility) {
                AgentProviders.agents.compactMap { provider in
                    discovery.latest(provider: provider, project: project, workspace: workspace)
                        .map { (provider: provider, id: $0) }
                }
            }.value
            guard !Task.isCancelled, document.sessionID == documentSession else { return }
            var names: [String] = []
            for match in found where sessionBookmarks[match.provider.id].isEmpty {
                sessionBookmarks[match.provider.id] = match.id
                names.append(match.provider.title)
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
                let identifier = await Task.detached(priority: .utility) {
                    discovery.latest(
                        provider: provider, project: project, workspace: workspace,
                        notBefore: launchedAt)
                }.value
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "BashCut Agent")
        window.minSize = NSSize(width: 360, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AgentDockView(model: self, detached: true))
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
