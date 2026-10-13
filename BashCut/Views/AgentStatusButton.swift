import BashCutAutomation
import SwiftUI

/// The toolbar's agent button (#534): what the agent is doing (idle, working on a stage, waiting for the user,
/// finished). A click opens the run panel and a second click closes it (`ui action run.toggle`). Compact: the icon,
/// with the state in its help.
struct AgentStatusButton: View {
    let document: ProjectDocument
    let compact: Bool

    var body: some View {
        let status = document.activity.status
        Button { document.run(.toggleRunPanel) } label: {
            HStack(spacing: 5) {
                icon(status)
                if !compact { Text(Self.label(status)).lineLimit(1).frame(maxWidth: 150, alignment: .leading) }
            }
            .font(.caption)
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.tint(status).opacity(status == .idle ? 0 : 0.16)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(
                document.runPanel.visible ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.help(status, open: document.runPanel.visible))
        .accessibilityLabel(String(localized: "Agent run") + ", " + Self.label(status))
        .action(.toggleRunPanel, in: document)
    }

    @ViewBuilder private func icon(_ status: AgentStatus) -> some View {
        switch status {
        case .idle: Image(systemName: "wand.and.stars").foregroundStyle(.secondary)
        case .working: ProgressView().controlSize(.mini)
        case .waiting: Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
        case .finished: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        }
    }

    static func label(_ status: AgentStatus) -> String {
        switch status {
        case .idle: String(localized: "Agent")
        case .working(let what): what
        case .waiting: String(localized: "Waiting for you")
        case .finished: String(localized: "Agent run finished")
        }
    }

    static func tint(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: .clear
        case .working: .cyan
        case .waiting: .orange
        case .finished: .green
        }
    }

    private static func help(_ status: AgentStatus, open: Bool) -> String {
        let state: String = switch status {
        case .idle: String(localized: "The agent is idle")
        case .working(let what): String(format: String(localized: "The agent is working: %@"), what)
        case .waiting: String(localized: "The agent is waiting for your answer")
        case .finished: String(localized: "Agent run finished")
        }
        return state + " · " + (open ? String(localized: "Close the run panel") : String(localized: "Open the run panel"))
    }
}
