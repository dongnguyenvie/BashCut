import SwiftUI

/// The agent dock's banner for setting up the agent kit in Claude Code and Codex outside BashCut. Set Up does what
/// `agent setup claude|codex` does; Details opens Settings › Agents (`show.agent-kit`); Later is `agent.kit-later`.
struct AgentKitBanner: View {
    @Bindable var model: AgentDockModel
    let prompt: AgentKitPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain.head.profile").font(.title3).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                if model.kitSettingUp {
                    ProgressView().controlSize(.small)
                    Text("Setting up…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(prompt.outdated ? "Update" : "Set Up") { model.setUpKitFromPrompt() }
                        .buttonStyle(.borderedProminent)
                    Button("Details…") { model.document.run(.showAgentKit) }
                }
                Spacer()
                Button("Later") { model.document.run(.dismissAgentKitPrompt) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.kitSettingUp)
            }.controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.35)))
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var title: String {
        prompt.outdated
            ? String(format: String(localized: "Update the BashCut skills for %@"), prompt.agentNames)
            : String(format: String(localized: "Give %@ the BashCut skills"), prompt.agentNames)
    }

    private var detail: String {
        // One key, so translators see the whole sentence.
        // swiftlint:disable:next line_length
        let format = String(localized: "The agent kit is the agent's brain for BashCut: %d editing skills and the BashCut tools. BashCut's tabs load it already; set it up so %@ in your own terminal can edit your projects too.")
        return String(format: format, prompt.skills, prompt.agentNames)
    }
}
