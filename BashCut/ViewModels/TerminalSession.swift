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
    let view = AgentTerminalView(frame: .zero)
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
    var isRunning: Bool { view.process?.running ?? false }

    /// The lines on screen.
    var screenText: String {
        let terminal = view.getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
            .joined(separator: "\n")
    }

    enum Readiness { case ready, quit, cancelled }

    /// Waits until the agent takes input: it has printed, then stayed quiet for `quiet`, and shows no menu
    /// (`AgentScreen.isAsking`, such as trusting the folder). A just-started CLI draws its input box only after
    /// loading, and a paste before that is lost or answers the menu. `asking` hears when a menu shows or goes, so the
    /// user can answer it; the wait then lasts up to `askTimeout`. An agent that keeps animating counts as ready
    /// after `timeout`.
    func waitUntilReady(
        quiet: Duration = .milliseconds(800), timeout: Duration = .seconds(20), askTimeout: Duration = .seconds(600),
        asking: (Bool) -> Void = { _ in }
    ) async -> Readiness {
        let clock = ContinuousClock()
        let start = clock.now
        var wasAsking = false
        while isRunning {
            let settled = view.lastOutput.map { clock.now - $0 >= quiet } ?? false
            let isAsking = settled && AgentScreen.isAsking(screenText)
            if isAsking != wasAsking {
                wasAsking = isAsking
                asking(isAsking)
            }
            if settled, !isAsking { return .ready }
            if clock.now - start >= (isAsking ? askTimeout : timeout) { return isAsking ? .cancelled : .ready }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return .cancelled }
        }
        return .quit
    }

    /// Presses Return in the terminal, sending what is in the agent's input.
    func submit() { view.send(source: view, data: [13][...]) }
    /// Presses Escape, which interrupts Claude Code's and Codex's current turn (the run panel's Stop, #534).
    func interrupt() { view.send(source: view, data: [27][...]) }
    func runCommand(_ text: String) { view.send(source: view, data: Array((text + "\n").utf8)[...]) }
    func close() {
        view.send(source: view, data: [3][...])
        view.terminate()
    }
}

/// The terminal, noting when its program last printed (`TerminalSession.waitUntilReady`).
final class AgentTerminalView: LocalProcessTerminalView {
    private(set) var lastOutput: ContinuousClock.Instant?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutput = .now
        super.dataReceived(slice: slice)
    }
}
