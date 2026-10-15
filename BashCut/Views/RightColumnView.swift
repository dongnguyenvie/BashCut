import BashCutDocument
import SwiftUI

/// The right column (P1-6, D1): Inspector and Agent as tabs. The Agent tab shows a dot while the agent works.
struct RightColumnView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tab(.inspector, title: "Inspector", systemImage: "slider.horizontal.3")
                tab(.agent, title: "Agent", systemImage: "terminal")
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            switch document.ui.rightTab {
            case .inspector:
                InspectorView(document: document)
            case .agent:
                if document.agents.isDetached {
                    PoppedOutAgentView(model: document.agents)
                } else {
                    AgentDockView(model: document.agents)
                }
            }
        }.background(Color(red: 0.045, green: 0.05, blue: 0.06))
    }

    private func tab(_ tab: RightColumnTab, title: LocalizedStringKey, systemImage: String) -> some View {
        let selected = document.ui.rightTab == tab
        return Button {
            document.ui.selectRightTab(tab)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                if tab == .agent, let dot = agentDot { Circle().fill(dot).frame(width: 6, height: 6) }
            }
            .foregroundStyle(selected ? Color.cyan : Color.primary.opacity(0.65))
            .padding(.horizontal, 9).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(selected ? 0.08 : 0)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.cyan.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Cyan while the agent works, orange while it waits for the user.
    private var agentDot: Color? {
        switch document.activity.status {
        case .working: .cyan
        case .waiting: .orange
        case .idle, .finished: nil
        }
    }
}

/// The Agent tab while the agent runs in its own window.
private struct PoppedOutAgentView: View {
    let model: AgentDockModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Agent is in its own window").font(.headline).multilineTextAlignment(.center)
            HStack {
                Button("Show window") { model.detach() }
                Button("Bring back") { model.attach() }.buttonStyle(.borderedProminent)
            }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
