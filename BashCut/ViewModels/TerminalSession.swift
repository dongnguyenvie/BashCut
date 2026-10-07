import AppKit
import BashCutAgent
import BashCutProject
import Foundation
import Observation
import SwiftTerm

@MainActor @Observable final class TerminalSession: Identifiable, AgentScopeOwner {
    let id = UUID()
    let provider: any AgentProvider
    let token: String
    /// Items sent with Send to Agent (#356), shown as chips over the terminal until removed. Allow for this
    /// request lasts until the scope changes.
    var scope: [AgentScopeItem] = [] {
        didSet {
            scopeAllowed = false
            if scope.isEmpty { scopeExtra = [] }
        }
    }
    var scopeAllowed = false
    var scopeExtra: Set<String> = []
    var scopeLast: JSONValue?
    var question: AgentQuestionPrompt? // agent.ask's card over the terminal, until it is answered
    let launchedAt = Date()
    let view = LocalProcessTerminalView(frame: .zero)
    var title: String
    /// SF Symbol for the tab.
    let icon: String
    init(provider: any AgentProvider, token: String, launch: AgentLaunch, icon: String) {
        self.provider = provider
        self.token = token
        self.icon = icon
        title = provider.title
        view.menu = EditMenus.terminalContextMenu(for: view)
        view.startProcess(
            executable: launch.executable, args: launch.arguments,
            environment: launch.environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: launch.directory)
    }
    /// Presses Return in the terminal, sending what is in the agent's input.
    func submit() { view.send(source: view, data: [13][...]) }
    func runCommand(_ text: String) { view.send(source: view, data: Array((text + "\n").utf8)[...]) }
    func close() {
        view.send(source: view, data: [3][...])
        view.terminate()
    }
}
