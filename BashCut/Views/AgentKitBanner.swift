import SwiftUI

/// The agent dock's banner for setting up the agent kit in Claude Code and Codex outside BashCut. Set Up does what
/// `agent setup claude|codex` does; Details opens Settings › Agents (`show.agent-kit`); Later is `agent.kit-later`.
struct AgentKitBanner: View {
    @Bindable var model: AgentDockModel
    let prompt: AgentKitPrompt
    /// The full card shows the first time this kit version is seen; after that it takes one line (P1-8).
    @State private var collapsed: Bool
    /// One line without its own background, inside the dock's setup steps.
    private let compact: Bool

    init(model: AgentDockModel, prompt: AgentKitPrompt, compact: Bool = false) {
        self.model = model
        self.prompt = prompt
        self.compact = compact
        _collapsed = State(initialValue: compact || model.settings.agentKitPromptSeen == prompt.version)
    }

    var body: some View {
        Group {
            if collapsed { line } else { card }
        }.onAppear { model.settings.agentKitPromptSeen = prompt.version }
    }

    private var line: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile").foregroundStyle(.cyan)
            Text("Agent skills:").foregroundStyle(.secondary)
            if model.kitSettingUp {
                ProgressView().controlSize(.mini)
                Text("Setting up…").foregroundStyle(.secondary)
            } else {
                Button(prompt.outdated ? "Update" : "Set Up") { model.setUpKitFromPrompt() }.buttonStyle(.link)
                Text("·").foregroundStyle(.secondary)
                Button("Details…") { model.document.run(.showAgentKit) }.buttonStyle(.link)
            }
            Spacer(minLength: 0)
            Button("Later") { model.document.run(.dismissAgentKitPrompt) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.kitSettingUp)
        }
        .font(.caption).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6)
        .background(compact ? Color.clear : Color.cyan.opacity(0.08))
        .help(detail)
    }

    private var card: some View {
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
