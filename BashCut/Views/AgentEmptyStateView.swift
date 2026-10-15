import BashCutAgent
import SwiftUI

/// The Agent tab before any agent runs (P1-8): one primary button for the default agent, an "Other agents" menu for
/// the rest, the one-line explainer, and quick starts for the project's state.
struct AgentEmptyStateView: View {
    @Bindable var model: AgentDockModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                start
                BriefQuickStartView(model: model)
            }.padding(12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var start: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.cyan)
            Button(primaryTitle) { model.openDefault() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Menu("Other agents") { otherAgents }
                .menuStyle(.borderlessButton).fixedSize()
            Text("Claude Code and Codex run with your CLI login or API key.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !model.sessionDiscoveryMessage.isEmpty {
                Label(model.sessionDiscoveryMessage, systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity).padding(.top, 8)
    }

    private var defaultTitle: String {
        model.agentChoices.first { $0.id == model.defaultProvider }?.title ?? model.defaultProvider.rawValue
    }

    /// "Continue Claude Code" when this project has a conversation to pick up, otherwise "Start Claude Code".
    private var primaryTitle: String {
        if model.canContinue(model.defaultProvider) {
            return String(format: String(localized: "Continue %@"), defaultTitle)
        }
        return String(format: String(localized: "Start %@"), defaultTitle)
    }

    @ViewBuilder private var otherAgents: some View {
        if model.canContinue(model.defaultProvider) {
            Button(String(format: String(localized: "New conversation with %@"), defaultTitle)) {
                model.startNewConversation(model.defaultProvider)
            }.help("Start without the earlier conversation")
        }
        ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
            Button(String(format: String(localized: "Start %@"), agent.title)) { model.openChat(agent.pluginID) }
        }
        ForEach(model.agentChoices.filter { $0.id != model.defaultProvider }) { choice in
            if model.canContinue(choice.id) {
                Button(String(format: String(localized: "Continue %@"), choice.title)) { model.open(choice.id) }
                    .help("Pick up your last conversation in this project")
                Button(String(format: String(localized: "New conversation with %@"), choice.title)) {
                    model.startNewConversation(choice.id)
                }.help("Start without the earlier conversation")
            } else {
                Button(String(format: String(localized: "Start %@"), choice.title)) { model.open(choice.id) }
            }
        }
    }
}
