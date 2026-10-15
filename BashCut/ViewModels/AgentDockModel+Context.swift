import BashCutAgent
import Foundation
import Observation

extension AgentDockModel {
    var hasOpenAgent: Bool { chatPluginID != nil || current != nil }

    /// Puts a request in the open agent's input and shows the dock; false when no agent is open.
    func ask(_ request: String) -> Bool {
        guard hasOpenAgent else { return false }
        fillInput(request)
        if !isDetached { document.ui.showAgentDock = true }
        return true
    }

    /// Puts `request` in the open agent's input for the user to send: the chat draft, or a paste in the terminal.
    /// Only the request goes in; agents read the live selection and playhead with `context get`.
    func fillInput(_ request: String, imageURL: URL? = nil) {
        if let chatPluginID {
            let agent = document.chatAgents.model(for: chatPluginID)
            agent.draft = request
            agent.draftImage = imageURL
        } else if let session = current {
            let text = AgentRequest.paste(request, image: imageURL)
            if !text.isEmpty { session.paste(text) }
        }
    }

    /// Send to Agent: attaches timeline items to the open agent's request. A chat tab shows them as chips that every
    /// message carries; a terminal shows them as chips too and gets the scope pasted in its input, before the request
    /// the user types. With no
    /// agent open it opens the first chat agent, or shows the dock when there is none. Returns the chat agent the
    /// items went to, or nil for a terminal or when nothing was attached.
    @discardableResult
    func sendToAgent(_ ids: [String]) -> ChatAgentModel? {
        let items = AgentScope.items(ids, in: document.project)
        guard !items.isEmpty else { return nil }
        if !isDetached { document.ui.showAgentDock = true }
        if chatPluginID == nil, current == nil, let first = document.chatAgents.available.first {
            openChat(first.pluginID)
        }
        if let chatPluginID {
            let agent = document.chatAgents.model(for: chatPluginID)
            agent.scope = AgentScope.merge(agent.scope, items)
            return agent
        }
        if let session = current {
            session.scope = AgentScope.merge(session.scope, items)
            session.paste(AgentScope.text(items, fps: document.project.fps) + "\n")
        } else {
            document.message = String(localized: "Open an agent in the dock, then send the clips to it again.")
        }
        return nil
    }

    /// Sends the New brief draft (with the viewer frame when attached) to the brief's target, starting the agent first
    /// when it is not open, then clears it and closes the sheet. On failure the brief stays and the sheet says why.
    func sendAsk() async {
        let typed = askModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !askModel.sending else { return }
        let request = BriefFootage.request(typed, items: askModel.footage)
        askModel.sending = true
        askModel.error = ""
        defer {
            askModel.sending = false
            askModel.status = ""
        }
        do {
            askModel.status = askModel.attachFrame ? String(localized: "Preparing frame…") : ""
            let image = askModel.attachFrame ? try await document.captureAgentFrame() : nil
            switch briefTarget {
            case .chat(let pluginID):
                let agent = document.chatAgents.model(for: pluginID)
                guard !agent.running else {
                    askModel.error = String(format: String(localized: "%@ is still answering. Send when it finishes."), agent.title)
                    return
                }
                openChat(pluginID)
                if !isDetached { document.ui.showAgentDock = true }
                agent.send(request, imageURL: image)
            case .session(let id):
                guard let session = sessions.first(where: { $0.id == id }) else { return }
                selectedSession = id
                chatPluginID = nil
                guard try await deliver(request, image: image, to: session) else { return }
            case .start(let provider):
                guard try await deliver(request, image: image, to: startForBrief(provider)) else { return }
            }
            recordRecentBrief(typed)
            askModel.footage = []
            askModel.draft = ""
            askModel.edited = false
            askModel.target = nil
            document.ui.showAsk = false
        } catch {
            askModel.error = error.localizedDescription
        }
    }

    /// Opens a new tab of `provider` for the brief.
    private func startForBrief(_ provider: AgentProviderID) async throws -> TerminalSession {
        let title = agentChoices.first { $0.id == provider }?.title ?? provider.rawValue
        askModel.status = String(format: String(localized: "Starting %@…"), title)
        if let builtIn = AgentProviders.provider(provider) { return try await startBuiltIn(builtIn) }
        return try await openPluginTerminal(provider.rawValue)
    }

    /// Pastes the brief in a terminal once its agent takes input, then presses Return. When the agent shows a menu
    /// first (trusting the folder), the sheet closes so the user can answer it in the dock, and the brief follows.
    /// False when it was not sent.
    private func deliver(_ request: String, image: URL?, to session: TerminalSession) async throws -> Bool {
        if session.provider.isAgent { settings.lastAgentRaw = session.provider.id.rawValue }
        if !isDetached { document.ui.showAgentDock = true }
        askModel.status = String(format: String(localized: "Waiting for %@…"), session.title)
        let readiness = await session.waitUntilReady { [weak self] asking in
            guard let self, asking else { return }
            document.ui.showAsk = false
            document.message = String(
                format: String(localized: "Answer %@ in the dock; the brief is sent after that."), session.title)
        }
        let failure: String? = switch readiness {
        case .ready: nil
        case .quit: String(format: String(localized: "%@ quit before the brief was sent."), session.title)
        case .cancelled: Task.isCancelled ? "" : String(
            format: String(localized: "The brief was not sent: %@ still waits for an answer."), session.title)
        }
        if let failure {
            askModel.error = failure
            if !failure.isEmpty { document.message = failure }
            return false
        }
        session.paste(AgentRequest.paste(request, image: image))
        // The agent reads the paste first; an Enter in the same write could land inside it.
        try await Task.sleep(for: .milliseconds(200))
        session.submit()
        return true
    }

    /// Send in the New brief sheet; Cancel stops it while it waits for the agent.
    func startSendAsk() {
        askModel.sendTask = Task { await sendAsk() }
    }
}

extension TerminalSession {
    func paste(_ text: String) {
        // Bracketed paste prevents multiline context from becoming immediate shell commands. An agent that drops a
        // paste's last newline gets it as a key after the paste instead (`newlineAfterPaste`).
        var safe = text.replacingOccurrences(of: "\u{1b}", with: "")
        let newline = safe.hasSuffix("\n") ? provider.newlineAfterPaste : nil
        if newline != nil { safe.removeLast() }
        view.send(source: view, data: Array(("\u{1b}[200~" + safe + "\u{1b}[201~").utf8)[...])
        if let newline { view.send(source: view, data: newline[...]) }
    }
}
