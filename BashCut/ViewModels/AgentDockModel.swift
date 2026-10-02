import AppKit
import BashCutAgent
import BashCutAutomation
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
    let provider: TerminalProvider
    let token: String
    let view = LocalProcessTerminalView(frame: .zero)
    var title: String
    init(provider: TerminalProvider, token: String, launch: AgentLaunch) {
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
    var resumeProviderRaw = TerminalProvider.codex.rawValue
    var sessionBookmarks = AgentSessionBookmarks()
    var sessionDiscoveryMessage = ""
    var workspace: URL?
    var defaultProviderRaw = TerminalProvider.codex.rawValue
    var allowAgentEdits = true
    var defaultExportPresetRaw = "tiktok"
    var interfaceLanguage = "system"
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
        if let path = UserDefaults.standard.string(forKey: "agentWorkspace") {
            workspace = URL(fileURLWithPath: path)
        }
        defaultProviderRaw = UserDefaults.standard.string(forKey: "defaultAgent") ?? "codex"
        allowAgentEdits = UserDefaults.standard.object(forKey: "allowAgentEdits") as? Bool ?? true
        defaultExportPresetRaw = UserDefaults.standard.string(forKey: "defaultExportPreset") ?? "tiktok"
        interfaceLanguage = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system"
    }
    var current: TerminalSession? { sessions.first { $0.id == selectedSession } }
    var defaultProvider: TerminalProvider {
        TerminalProvider(rawValue: defaultProviderRaw) ?? .codex
    }
    var isDetached: Bool { detachedWindow != nil }
    var directory: URL {
        workspace ?? document.fileURL?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
    var toolsDirectory: String { Bundle.main.executableURL?.deletingLastPathComponent().path ?? "" }
    var resumeProvider: TerminalProvider {
        TerminalProvider(rawValue: resumeProviderRaw) ?? .codex
    }
    var resumeID: String {
        get { resumeProvider == .claude ? sessionBookmarks.claude : sessionBookmarks.codex }
        set {
            if resumeProvider == .claude {
                sessionBookmarks.claude = newValue
            } else {
                sessionBookmarks.codex = newValue
            }
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace = url
        UserDefaults.standard.set(url.path, forKey: "agentWorkspace")
        document.rebuild()
    }
    func savePreferences() {
        UserDefaults.standard.set(defaultProviderRaw, forKey: "defaultAgent")
        UserDefaults.standard.set(allowAgentEdits, forKey: "allowAgentEdits")
        UserDefaults.standard.set(defaultExportPresetRaw, forKey: "defaultExportPreset")
        UserDefaults.standard.set(interfaceLanguage, forKey: "interfaceLanguage")
        if interfaceLanguage == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([interfaceLanguage], forKey: "AppleLanguages")
        }
    }
    func applyAgentEditPreference() {
        if !allowAgentEdits {
            for session in sessions where session.provider != .shell {
                document.registry.revoke(session.token)
            }
        }
        savePreferences()
    }
    func openDefault() { open(defaultProvider) }
    func open(_ provider: TerminalProvider) {
        knowledge.load(from: directory)
        let author: Author = provider == .claude ? .claude : provider == .codex ? .codex : .user
        let canEdit = provider == .shell || allowAgentEdits
        let token = canEdit ? document.registry.issueToken(author: author) : ""
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
            if provider != .shell {
                if resumeID(for: provider).isEmpty {
                    discoverLaunchedSession(
                        provider: provider, workspace: URL(fileURLWithPath: launch.directory),
                        session: session.id, launchedAt: launchedAt)
                } else {
                    saveResumeID()
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
    func saveResumeID() {
        guard let project = document.fileURL else { return }
        do {
            try sessionStore.save(sessionBookmarks, project: project)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
    func handoff(to provider: TerminalProvider) {
        guard provider != .shell else { return }
        let source = current?.provider.title ?? "BashCut"
        let launchesTarget = !sessions.contains(where: { $0.provider == provider })
        if launchesTarget { open(provider) }
        guard let target = sessions.last(where: { $0.provider == provider }) else { return }
        selectedSession = target.id
        apiVisible = false
        knowledge.load(from: directory)
        let handoff =
            "Continue this editing task handed off from \(source).\n"
                + document.contextText() + "\n" + document.timelineText() + "\n" + knowledge.context
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
    private func resumeID(for provider: TerminalProvider) -> String {
        switch provider {
        case .claude: return sessionBookmarks.claude.trimmingCharacters(in: .whitespacesAndNewlines)
        case .codex: return sessionBookmarks.codex.trimmingCharacters(in: .whitespacesAndNewlines)
        case .shell: return ""
        }
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
                (
                    discovery.latest(provider: .claude, project: project, workspace: workspace),
                    discovery.latest(provider: .codex, project: project, workspace: workspace)
                )
            }.value
            guard !Task.isCancelled, document.sessionID == documentSession else { return }
            var names: [String] = []
            if sessionBookmarks.claude.isEmpty, let identifier = found.0 {
                sessionBookmarks.claude = identifier
                names.append("Claude")
            }
            if sessionBookmarks.codex.isEmpty, let identifier = found.1 {
                sessionBookmarks.codex = identifier
                names.append("Codex")
            }
            guard !names.isEmpty else { return }
            saveResumeID()
            sessionDiscoveryMessage = String(
                format: String(localized: "Found a resumable %@ session"),
                names.joined(separator: " / "))
        }
    }

    fileprivate func discoverLaunchedSession(
        provider: TerminalProvider, workspace: URL, session: UUID, launchedAt: Date
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
                if provider == .claude {
                    guard sessionBookmarks.claude.isEmpty else { return }
                    sessionBookmarks.claude = identifier
                } else {
                    guard sessionBookmarks.codex.isEmpty else { return }
                    sessionBookmarks.codex = identifier
                }
                saveResumeID()
                sessionDiscoveryMessage = String(
                    format: String(localized: "Saved %@ session for this project"), provider.title)
                return
            }
        }
    }

    func detach() {
        if let detachedWindow {
            detachedWindow.makeKeyAndOrderFront(nil)
            return
        }
        document.showAgentDock = false
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
            self?.document.showAgentDock = true
        }
        detachedDelegate = delegate
        window.delegate = delegate
        detachedWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func attach() {
        guard let window = detachedWindow else {
            document.showAgentDock = true
            return
        }
        detachedWindow = nil
        detachedDelegate = nil
        window.delegate = nil
        window.close()
        document.showAgentDock = true
    }
}
