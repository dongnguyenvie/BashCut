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
                if detached {
                    Text("AGENT").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    DockIconButton(systemImage: "rectangle.portrait.and.arrow.forward", help: "Attach agent dock") {
                        model.attach()
                    }
                } else {
                    Button { model.detach() } label: {
                        Label("Pop out", systemImage: "macwindow.on.rectangle").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Open the agent in its own window")
                    Spacer()
                }
                AgentSetupChip(model: model).padding(.trailing, 4)
                DockIconButton(systemImage: "books.vertical", help: knowledgeHelp) {
                    if model.knowledge.proposalCount > 0 { model.document.ui.knowledgeSection = "inbox" }
                    model.openKnowledge()
                }
                .overlay(alignment: .topTrailing) { knowledgeBadge }
                .task(id: model.document.fileURL) {
                    // The badge follows agents' writes while the Knowledge window is closed.
                    while !Task.isCancelled {
                        await model.refreshKnowledgeBadge()
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
                    Divider()
                    Button(String(format: String(localized: "Workspace: %@…"), model.directory.lastPathComponent)) {
                        model.chooseWorkspace()
                    }
                    .help("The folder agent terminals start in")
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 24, height: 22).help("New terminal, handoff or workspace")
            }.padding(.horizontal, 10).padding(.vertical, 8)
            tabs
            Divider()
            AgentSetupStepsView(model: model)
            if let key = model.pluginViewKey, let model = model.document.pluginViews.model(key: key) {
                PluginViewColumn(model: model)
            } else if let pluginID = model.chatPluginID {
                ChatAgentPanel(agent: model.document.chatAgents.model(for: pluginID), document: model.document)
            } else if let session = model.current {
                if !session.scope.isEmpty {
                    TerminalScopeBar(session: session, fps: model.document.project.fps)
                    Divider()
                }
                TerminalPanel(session: session).id(session.id)
                    .padding(.leading, 6).padding(.top, 4)
                    .background(Color(nsColor: session.view.nativeBackgroundColor))
                    .overlay(alignment: .bottom) {
                        if let question = session.question {
                            AgentQuestionCard(prompt: question, agent: session.title).id(ObjectIdentifier(question))
                        }
                    }
            } else {
                AgentEmptyStateView(model: model)
            }
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(.orange).padding(8).textSelection(.enabled)
            }
            Divider()
            quickActions
        }.background(Color(red: 0.045, green: 0.05, blue: 0.06))
            .task { await model.refreshKitPrompt() }
    }
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.sessions) { session in
                    DockTab(
                        title: session.title, systemImage: session.icon,
                        selected: model.selectedSession == session.id && model.chatPluginID == nil
                            && model.pluginViewKey == nil,
                        select: {
                            model.selectedSession = session.id
                            model.chatPluginID = nil
                            model.pluginViewKey = nil
                        },
                        close: { model.close(session) })
                }
                ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
                    DockTab(
                        title: agent.title, systemImage: "bubble.left.and.text.bubble.right",
                        selected: model.chatPluginID == agent.pluginID && model.pluginViewKey == nil,
                        select: { model.openChat(agent.pluginID) }, close: nil)
                }
                // Plugin views that live in the dock (plugin API 8).
                ForEach(model.document.pluginViews.dockViews, id: \.key) { entry in
                    DockTab(
                        title: entry.view.title.text,
                        systemImage: entry.view.icon ?? entry.plugin.manifest.container?.icon ?? "puzzlepiece.extension",
                        selected: model.pluginViewKey == entry.key,
                        select: { model.pluginViewKey = entry.key }, close: nil)
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

extension AgentDockView {
    /// Buttons for the project's state (New project, Survey footage, Review…), and under them, for a terminal or a
    /// plugin view, the brief bar: a terminal has no message box, so New brief looks like one. Chat tabs keep their
    /// own composer.
    var quickActions: some View {
        VStack(spacing: 8) {
            if !model.quickActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(model.quickActions.enumerated()), id: \.element.id) { index, quick in
                        Button(quick.title) { model.perform(quick) }
                            .buttonStyle(QuickActionStyle(primary: index == 0))
                            .disabled(!quickEnabled(quick))
                    }
                    Spacer(minLength: 0)
                }
            }
            if model.chatPluginID == nil || model.pluginViewKey != nil {
                BriefBar(agent: model.choice(for: model.briefTarget)?.title) { model.openBrief() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func quickEnabled(_ quick: BriefQuickAction) -> Bool {
        if case .action(let action) = quick.kind { return model.document.canPerform(action) }
        return true
    }

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

/// A quick action: the main one outlined in cyan.
private struct QuickActionStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let tint: SwiftUI.Color = primary ? .cyan : Color.primary.opacity(0.85)
        let fill: SwiftUI.Color = primary ? Color.cyan.opacity(configuration.isPressed ? 0.25 : 0.12)
            : Color.white.opacity(configuration.isPressed ? 0.12 : 0.05)
        let stroke: SwiftUI.Color = primary ? Color.cyan.opacity(0.6) : Color.white.opacity(0.1)
        return configuration.label.font(.caption).lineLimit(1)
            .padding(.horizontal, 9).frame(height: 24)
            .foregroundStyle(tint)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stroke, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// New brief (⌘K) drawn as a message field under a terminal: "Tell Claude Code what to make…".
private struct BriefBar: View {
    let agent: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundStyle(.cyan)
                Text(placeholder).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text("⌘K").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovered ? 0.09 : 0.055)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(hovered ? Color.cyan.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("New brief… (⌘K)")
        .accessibilityLabel(placeholder)
        .accessibilityHint("Opens New brief")
    }

    private var placeholder: String {
        String(format: String(localized: "Tell %@ what to make…"), agent ?? String(localized: "the agent"))
    }
}

/// A 22 pt icon button with a hover highlight for the dock header.
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
