import BashCutAgent
import BashCutAutomation
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// `agent terminals|open|detach`: the dock's terminal tabs, built-in and from `agent.terminal` plugins
    /// (docs/specs/12-terminal-agents.md), from the CLI and MCP.
    func registerTerminalCommands() {
        handle("agent.terminals") { document, _, _ in
            let agents = document.agents
            let terminals: [JSONValue] = agents.terminalChoices.map { choice in
                var fields: [String: JSONValue] = [
                    "id": .string(choice.id.rawValue), "title": .string(choice.title),
                    "kind": .string(choice.pluginID == nil ? "built-in" : "plugin"), "agent": .bool(choice.isAgent),
                    "canContinue": .bool(choice.isAgent && agents.canContinue(choice.id)),
                ]
                if let plugin = choice.pluginID { fields["plugin"] = .string(plugin) }
                return .object(fields)
            }
            let ready = Set(agents.terminalPlugins.map(\.id))
            let unavailable: [JSONValue] = document.plugins.plugins
                .filter { $0.manifest.terminal != nil && !ready.contains($0.id) }
                .map { plugin in
                    .object([
                        "plugin": .string(plugin.id), "name": .string(plugin.manifest.displayName),
                        "reason": .string(document.plugins.availability[plugin.id]?.detail ?? "Not checked yet"),
                    ])
                }
            let tabs: [JSONValue] = agents.sessions.map { session in
                .object([
                    "terminal": .string(session.provider.id.rawValue), "title": .string(session.title),
                    "selected": .bool(agents.selectedSession == session.id && agents.chatPluginID == nil),
                    "scope": .array(session.scope.map(\.json)),
                ])
            }
            return .object([
                "terminals": .array(terminals), "unavailable": .array(unavailable), "tabs": .array(tabs),
            ])
        }
        handle("agent.detach") { document, arguments, _ in
            guard let session = document.agents.current, document.agents.chatPluginID == nil else {
                throw RPCFailure(-32602, "No terminal tab is shown; chat tabs use chat detach")
            }
            let ids = Set((arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            session.scope.removeAll { ids.isEmpty || ids.contains($0.id) || $0.linked.map(ids.contains) == true }
            return .object([
                "terminal": .string(session.provider.id.rawValue), "scope": .array(session.scope.map(\.json)),
            ])
        }
        handle("agent.open") { document, arguments, _ in
            let agents = document.agents
            let id = AgentProviderID(rawValue: try arguments.string("terminal"))
            guard let choice = agents.terminalChoices.first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "No terminal \(id.rawValue); agent terminals lists them")
            }
            if arguments.bool("new"), choice.isAgent {
                agents.sessionBookmarks[id] = ""
                agents.saveSessionBookmarks()
            }
            let continues = choice.isAgent && agents.canContinue(id)
            if !agents.isDetached { document.ui.showAgentDock = true }
            let session = try await {
                if let provider = AgentProviders.provider(id) { return try agents.startBuiltIn(provider) }
                return try await agents.openPluginTerminal(id.rawValue)
            }()
            return .object([
                "terminal": .string(id.rawValue), "title": .string(session.title), "continued": .bool(continues),
            ])
        }
    }
}
