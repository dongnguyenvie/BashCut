import BashCutAutomation
import BashCutProject
import Foundation

extension ProjectDocument {
    /// `chat status|send|stop|reset|transcript`: the dock's chat-agent tabs (plugins with `agent.chat`) from the
    /// CLI and MCP. `--plugin` picks the agent; by default the one whose tab is shown, else the first ready one.
    func registerChatAgentCommands() {
        handle("chat.status") { document, _, _ in
            var agents: [JSONValue] = []
            for agent in document.chatAgents.available {
                await agent.refreshStatus()
                agents.append(.object([
                    "plugin": .string(agent.pluginID), "name": .string(agent.title),
                    "running": .bool(agent.running), "status": agent.status ?? .null,
                ]))
            }
            return .object(["agents": .array(agents)])
        }
        handle("chat.send") { document, arguments, _ in
            let agent = try document.chatAgents.target(arguments.optionalString("plugin"))
            guard !agent.running else { throw RPCFailure(-32602, "\(agent.title) is already working; stop it first") }
            let image = arguments.optionalString("image").map { URL(fileURLWithPath: $0) }
            if let image, !FileManager.default.fileExists(atPath: image.path) {
                throw RPCFailure(-32602, "No image at \(image.path)")
            }
            if !document.agents.isDetached { document.ui.showAgentDock = true }
            document.agents.openChat(agent.pluginID)
            agent.send(try arguments.string("text"), imageURL: image)
            return .object(["plugin": .string(agent.pluginID), "started": .bool(true)])
        }
        handle("chat.stop") { document, arguments, _ in
            let agent = try document.chatAgents.target(arguments.optionalString("plugin"))
            agent.stop()
            return .object(["plugin": .string(agent.pluginID)])
        }
        handle("chat.reset") { document, arguments, _ in
            let agent = try document.chatAgents.target(arguments.optionalString("plugin"))
            await agent.reset()
            return .object(["plugin": .string(agent.pluginID), "reset": .bool(true)])
        }
        handle("chat.transcript") { document, arguments, _ in
            let agent = try document.chatAgents.target(arguments.optionalString("plugin"))
            var transcript = agent.transcriptJSON.object
            transcript["plugin"] = .string(agent.pluginID)
            return .object(transcript)
        }
    }
}
