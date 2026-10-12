import BashCutAgent
import BashCutAutomation
import BashCutProject
import Foundation

extension AgentDockModel {
    /// Sends a request BashCut worded (a quick edit, a result card follow-up) to the open agent as if the user typed
    /// and sent it: a chat tab gets it as a message, a terminal gets it pasted and submitted. `scope` replaces the
    /// attached clips (empty clears them, so a whole-edit request is not held to old chips). With no agent open it
    /// opens the first chat agent. Returns the chat plugin ID, or `terminal`.
    @discardableResult
    func deliver(_ request: String, scope ids: [String]) throws -> String {
        if chatPluginID == nil, current == nil, let first = document.chatAgents.available.first {
            openChat(first.pluginID)
        }
        let items = AgentScope.items(ids, in: document.project)
        if let chatPluginID {
            let agent = document.chatAgents.model(for: chatPluginID)
            guard !agent.running else { throw RPCFailure(-32003, "\(agent.title) is still working; wait or stop it first") }
            if !isDetached { document.ui.showAgentDock = true }
            agent.scope = items
            agent.send(request)
            return chatPluginID
        }
        guard let session = current else {
            throw RPCFailure(-32602, "Open an agent in the dock (a chat agent or a Claude or Codex tab) first")
        }
        if !isDetached { document.ui.showAgentDock = true }
        session.scope = items
        let scopeText = AgentScope.text(items, fps: document.project.fps)
        session.paste((scopeText.isEmpty ? "" : scopeText + "\n\n") + request)
        // The agent reads the paste first; an Enter in the same write could land inside it.
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            session.submit()
        }
        return "terminal"
    }

    /// Whether a request can go anywhere: an agent is open, or a chat agent can be opened.
    var canDeliver: Bool { hasOpenAgent || !document.chatAgents.available.isEmpty }
}

extension ProjectDocument {
    /// `agent.quick-edit` and the Quick Edit menu (#449): a one-click request on the selected clips (or `ids`),
    /// sent to the open agent with them as its scope and ending with a review of their range. Lower music adds the
    /// music under the range to the scope.
    @discardableResult
    func quickEdit(_ kind: QuickEdit, text: String? = nil, ids given: [String] = []) throws -> JSONValue {
        let ids = given.isEmpty ? selectedIDs : given
        let items = AgentScope.items(ids, in: project)
        guard let range = AgentFollowUp.range(items) else {
            throw RPCFailure(-32602, "Select the clips the quick edit is about (or give --items)")
        }
        let request: String
        do { request = try AgentFollowUp.quickEdit(kind, text: text, items: items) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        var scope = items.map(\.id)
        if kind == .musicLower {
            scope += AgentFollowUp.musicItems(under: range, in: project).filter { !scope.contains($0) }
        }
        let target = try agents.deliver(request, scope: scope)
        return .object([
            "kind": .string(kind.rawValue), "sentTo": .string(target), "items": .array(scope.map(JSONValue.string)),
            "range": .object(["from": .integer(range.lowerBound), "to": .integer(range.upperBound)]),
            "request": .string(request),
        ])
    }

    /// The result card's Fix remaining issues: the open review issues to the agent, then the same export again.
    func fixRunIssues() throws {
        guard let result = runPanel.result else { throw RPCFailure(-32602, "No run result yet") }
        try agents.deliver(
            AgentFollowUp.fixIssues(errors: result.errors, warnings: result.warnings, output: result.main.path), scope: [])
    }

    /// The result card's Try another recipe: a new version with another recipe, this one kept.
    func tryAnotherRecipe() throws {
        let current = project["plan"]?.object["recipe"]?.object["skill"]?.string
        try agents.deliver(AgentFollowUp.anotherRecipe(current: current, recipe: nil), scope: [])
    }

    func registerFollowUpCommands() {
        handle("agent.quick-edit") { document, arguments, _ in
            guard let kind = QuickEdit(rawValue: try arguments.string("kind")) else {
                throw RPCFailure(-32602, "kind is one of " + QuickEdit.allCases.map(\.rawValue).joined(separator: ", "))
            }
            let ids = (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let known = Set(document.project.tracks.flatMap(\.items).map(\.id))
            if let unknown = ids.first(where: { !known.contains($0) }) { throw RPCFailure(-32602, "Unknown item \(unknown)") }
            return try document.quickEdit(kind, text: arguments.optionalString("text"), ids: ids)
        }
    }
}
