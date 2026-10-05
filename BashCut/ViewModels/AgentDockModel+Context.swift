import BashCutAgent
import BashCutEngine
import Foundation

extension AgentDockModel {
    /// Puts a request with the context in the open agent's input and shows the dock; false when no agent is open.
    func ask(_ request: String) -> Bool {
        guard chatPluginID != nil || current != nil else { return false }
        sendContext(request)
        if !isDetached { document.ui.showAgentDock = true }
        return true
    }

    func sendContext(_ request: String = "", imageURL: URL? = nil) {
        loadKnowledge()
        let context = document.contextText() + "\n" + knowledge.context
        if let chatPluginID {
            let agent = document.chatAgents.model(for: chatPluginID)
            var text = context + "\n" + request
            if let imageURL { text += "\nCurrent viewer frame: " + imageURL.path }
            agent.draft = request.isEmpty ? text : request
            agent.draftImage = imageURL
        } else if let session = current {
            // Terminals fold a long paste into a placeholder; paste the request and the context file's path.
            do {
                let file = try AgentContextFile.write(context, in: contextFolder)
                session.paste(AgentContextFile.prompt(request: request, context: file, image: imageURL))
            } catch {
                document.message = error.localizedDescription
            }
        }
    }

    /// The open project's agent-context cache, or a temporary folder before the project is saved.
    private var contextFolder: URL {
        if let root = document.fileURL?.deletingLastPathComponent() {
            return ProjectCache.url(.agentContext, projectRoot: root)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("BashCut-agent-context")
    }
}
