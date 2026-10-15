import BashCutAgent
import SwiftUI

/// What is left to set up before the agent can work, as one "N setup steps" row that opens to the steps: the agent
/// kit for Claude Code and Codex outside BashCut, and the shown chat agent's API key.
struct AgentSetupStepsView: View {
    @Bindable var model: AgentDockModel
    @State private var expanded = false

    private var kitPrompt: AgentKitPrompt? { model.showsKitPrompt ? model.kitPrompt : nil }

    /// The chat agent shown in the dock, when its plugin reported that it is not ready (no API key).
    private var chatNeedingKey: ChatAgentModel? {
        guard model.pluginViewKey == nil, let id = model.chatPluginID else { return nil }
        let agent = model.document.chatAgents.model(for: id)
        guard let status = agent.status?.object, status["ready"] != .bool(true) else { return nil }
        return agent
    }

    private var count: Int { (kitPrompt == nil ? 0 : 1) + (chatNeedingKey == nil ? 0 : 1) }

    var body: some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("\(count)").font(.caption.bold().monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange)).foregroundStyle(.black)
                        Text(title).font(.callout)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                if expanded { steps }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.35)))
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    private var title: String {
        count == 1 ? String(localized: "1 setup step for the agent")
            : String(format: String(localized: "%d setup steps for the agent"), count)
    }

    @ViewBuilder private var steps: some View {
        if let prompt = kitPrompt {
            Divider()
            AgentKitBanner(model: model, prompt: prompt, compact: true)
        }
        if let agent = chatNeedingKey {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "key").foregroundStyle(.orange)
                Text(agent.status?.object["detail"]?.string
                    ?? String(format: String(localized: "Add an API key for %@"), agent.title))
                    .foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button("Settings…") {
                    model.document.ui.settingsSection = "plugins"
                    model.document.ui.showSettings = true
                }.buttonStyle(.link)
            }
            .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
        }
    }
}
