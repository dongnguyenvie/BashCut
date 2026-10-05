import BashCutAgent
import Foundation
import Observation

/// The Ask agent sheet: a request written from a template, sent to the open agent.
@MainActor @Observable final class AgentAskModel {
    var draft = ""
    var attachFrame = false
    var sending = false
}

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

    /// Sends the Ask agent draft (with the viewer frame when attached), then clears it and closes the sheet.
    func sendAsk() async {
        let request = askModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, hasOpenAgent, !askModel.sending else { return }
        askModel.sending = true
        defer { askModel.sending = false }
        do {
            let image = askModel.attachFrame ? try await document.captureAgentFrame() : nil
            if !isDetached { document.ui.showAgentDock = true }
            if let chatPluginID {
                document.chatAgents.model(for: chatPluginID).send(request, imageURL: image)
            } else if let session = current {
                session.paste(AgentRequest.paste(request, image: image))
                // The agent reads the paste first; an Enter in the same write could land inside it.
                try? await Task.sleep(for: .milliseconds(200))
                session.submit()
            }
            askModel.draft = ""
            document.ui.showAsk = false
        } catch {
            document.message = error.localizedDescription
        }
    }
}
