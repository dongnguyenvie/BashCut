import AppKit
import BashCutAgent
import BashCutProject
import SwiftTerm
import SwiftUI

struct AgentDockView: View {
    @Bindable var model: AgentDockModel
    var detached = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text("AGENT").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                DockIconButton(
                    systemImage: detached ? "rectangle.portrait.and.arrow.forward" : "macwindow.on.rectangle",
                    help: detached ? "Attach agent dock" : "Detach agent dock"
                ) {
                    detached ? model.attach() : model.detach()
                }
                DockIconButton(systemImage: "books.vertical", help: knowledgeHelp) {
                    if model.knowledge.proposalCount > 0 { model.document.ui.knowledgeSection = "inbox" }
                    model.openKnowledge()
                }
                .overlay(alignment: .topTrailing) { knowledgeBadge }
                .task(id: model.document.fileURL) {
                    // The badge follows agents' writes while the Knowledge window is closed.
                    while !Task.isCancelled {
                        model.refreshKnowledgeBadge()
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
                Menu {
                    ForEach(model.terminalChoices) { choice in
                        Button("\(choice.title) terminal") { model.open(choice.id) }
                    }
                    ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
                        Button(agent.title) { model.openChat(agent.pluginID) }
                    }
                    Divider()
                    ForEach(model.agentChoices) { choice in
                        Button("Handoff to \(choice.title)") { model.handoff(to: choice.id) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 24, height: 22).help("New terminal or handoff")
            }.padding(.horizontal, 10).padding(.vertical, 8)
            tabs
            Divider()
            if model.showsKitPrompt, let prompt = model.kitPrompt {
                AgentKitBanner(model: model, prompt: prompt)
                Divider()
            }
            if let pluginID = model.chatPluginID {
                ChatAgentPanel(agent: model.document.chatAgents.model(for: pluginID), document: model.document)
            } else if let session = model.current {
                if !session.scope.isEmpty {
                    TerminalScopeBar(session: session, fps: model.document.project.fps)
                    Divider()
                }
                TerminalPanel(session: session).id(session.id)
                    .padding(.leading, 6).padding(.top, 4)
                    .background(Color(nsColor: session.view.nativeBackgroundColor))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.cyan)
                    Text("Choose an agent").font(.headline)
                    Text("Claude Code and Codex run with your CLI login or API key.").foregroundStyle(.secondary)
                    Button("Start default agent") { model.openDefault() }
                        .buttonStyle(.borderedProminent)
                    ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
                        Button(String(format: String(localized: "Start %@"), agent.title)) { model.openChat(agent.pluginID) }
                    }
                    ForEach(model.agentChoices) { choice in
                        if model.canContinue(choice.id) {
                            HStack {
                                Button("Continue \(choice.title)") { model.open(choice.id) }
                                    .help("Pick up your last conversation in this project")
                                Button("New conversation") { model.startNewConversation(choice.id) }
                                    .help("Start without the earlier conversation")
                            }
                        } else {
                            Button("Start \(choice.title)") { model.open(choice.id) }
                        }
                    }
                    if !model.sessionDiscoveryMessage.isEmpty {
                        Label(model.sessionDiscoveryMessage, systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(.orange).padding(8).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.directory.lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Workspace…", action: model.chooseWorkspace).font(.caption)
                }
                Button {
                    model.document.run(.askAgent)
                } label: {
                    Label("Ask agent…", systemImage: "square.and.pencil").font(.caption).lineLimit(1)
                }
                .help("Write a request from a template and send it to the agent")
                .disabled(!model.hasOpenAgent)
                HStack {
                    Button("Survey") {
                        model.fillInput("Survey the project footage and summarize missing coverage.")
                    }
                    Button("Write VO") {
                        model.fillInput("Draft voiceover without overlapping real speech.")
                    }
                    Button("Review") {
                        model.fillInput("Review the timeline for gaps, pacing and repeated framing.")
                    }
                }.font(.caption).disabled(!model.hasOpenAgent)
            }.padding(10)
        }.background(Color(red: 0.045, green: 0.05, blue: 0.06))
            .task { await model.refreshKitPrompt() }
    }
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.sessions) { session in
                    DockTab(
                        title: session.title, systemImage: session.icon,
                        selected: model.selectedSession == session.id && model.chatPluginID == nil,
                        select: {
                            model.selectedSession = session.id
                            model.chatPluginID = nil
                        },
                        close: { model.close(session) })
                }
                ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
                    DockTab(
                        title: agent.title, systemImage: "bubble.left.and.text.bubble.right",
                        selected: model.chatPluginID == agent.pluginID,
                        select: { model.openChat(agent.pluginID) }, close: nil)
                }
            }.padding(.horizontal, 8).padding(.vertical, 6)
        }.background(Color.white.opacity(0.03))
    }
}

/// A dock tab: provider icon and title, with a close button inside the tab that shows on hover or selection.
private struct DockTab: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let select: () -> Void
    let close: (() -> Void)?
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.white.opacity(hovered ? 0.12 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(selected || hovered ? 1 : 0)
                .help("Close \(title)")
            }
        }
        .foregroundStyle(selected ? Color.cyan : Color.primary.opacity(hovered ? 0.9 : 0.65))
        .padding(.leading, 9).padding(.trailing, close == nil ? 9 : 4).frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(selected ? 0.08 : hovered ? 0.05 : 0)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? Color.cyan.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
        .accessibilityAction(.default, select)
    }
}

/// A 22 pt icon button with a hover highlight for the dock header.
extension AgentDockView {
    /// Proposals waiting for review (orange count), or a dot when agents changed knowledge since the last visit.
    @ViewBuilder var knowledgeBadge: some View {
        let knowledge = model.knowledge
        if knowledge.proposalCount > 0 {
            Text("\(min(knowledge.proposalCount, 99))").font(.system(size: 8, weight: .bold).monospacedDigit())
                .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
                .background(Capsule().fill(Color.orange)).foregroundStyle(.black)
                .offset(x: 3, y: -2).allowsHitTesting(false)
        } else if knowledge.newTotal > 0 {
            Circle().fill(Color.cyan).frame(width: 6, height: 6).offset(x: -2, y: 2).allowsHitTesting(false)
        }
    }

    var knowledgeHelp: LocalizedStringKey {
        let knowledge = model.knowledge
        if knowledge.proposalCount > 0 { return "Knowledge: \(knowledge.proposalCount) waiting for review" }
        if knowledge.newTotal > 0 { return "Knowledge: \(knowledge.newTotal) new since your last visit" }
        return "Knowledge: lessons, preferences, facts and skills"
    }
}

private struct DockIconButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(hovered ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .onHover { hovered = $0 }
        .help(help)
    }
}

private struct TerminalPanel: NSViewRepresentable {
    let session: TerminalSession
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.view }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

/// The clips sent to a terminal agent (#356): the scope guard checks its edits against them until they are removed.
private struct TerminalScopeBar: View {
    let session: TerminalSession
    let fps: FrameRate

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ScopeChipsView(items: session.scope, fps: fps) { removed in
                session.scope.removeAll { $0.id == removed.id }
            }
            Spacer(minLength: 0)
            Button("Clear") { session.scope = [] }.buttonStyle(.link).font(.caption)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .help("The agent edits only these clips and asks before changing anything else.")
    }
}
