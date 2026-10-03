import AppKit
import BashCutAgent
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
                DockIconButton(systemImage: "books.vertical", help: "Skills and project memory") {
                    model.knowledge.load(from: model.directory)
                    model.showKnowledge = true
                }
                Menu {
                    ForEach(AgentProviders.all, id: \.id) { provider in
                        Button("\(provider.title) terminal") { model.open(provider.id) }
                    }
                    ForEach(model.document.chatAgents.available, id: \.pluginID) { agent in
                        Button(agent.title) { model.openChat(agent.pluginID) }
                    }
                    Divider()
                    ForEach(AgentProviders.agents, id: \.id) { provider in
                        Button("Handoff to \(provider.title)") { model.handoff(to: provider.id) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 24, height: 22).help("New terminal or handoff")
            }.padding(.horizontal, 10).padding(.vertical, 8)
            tabs
            Divider()
            if let pluginID = model.chatPluginID {
                ChatAgentPanel(agent: model.document.chatAgents.model(for: pluginID), document: model.document)
            } else if let session = model.current {
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
                    ForEach(AgentProviders.agents, id: \.id) { provider in
                        if model.canContinue(provider.id) {
                            HStack {
                                Button("Continue \(provider.title)") { model.open(provider.id) }
                                    .help("Pick up your last conversation in this project")
                                Button("New conversation") { model.startNewConversation(provider.id) }
                                    .help("Start without the earlier conversation")
                            }
                        } else {
                            Button("Start \(provider.title)") { model.open(provider.id) }
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
                    model.sendContext()
                } label: {
                    Label(
                        model.document.selectedID ?? String(localized: "Project context"), systemImage: "at"
                    )
                    .font(.caption).lineLimit(1)
                }.disabled(model.current == nil && model.chatPluginID == nil)
                HStack {
                    Button("Survey") {
                        model.sendContext("Survey the project footage and summarize missing coverage.")
                    }
                    Button("Write VO") {
                        model.sendContext("Draft voiceover without overlapping real speech.")
                    }
                    Button("Review") {
                        model.sendContext("Review the timeline for gaps, pacing and repeated framing.")
                    }
                }.font(.caption).disabled(model.current == nil && model.chatPluginID == nil)
            }.padding(10)
        }.background(Color(red: 0.045, green: 0.05, blue: 0.06))
            .sheet(isPresented: $model.showKnowledge) {
                AgentKnowledgeView(model: model.knowledge, done: { model.showKnowledge = false })
            }
    }
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.sessions) { session in
                    DockTab(
                        title: session.title, systemImage: Self.icon(for: session.provider.id),
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

    private static func icon(for provider: AgentProviderID) -> String {
        switch provider {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        default: "terminal"
        }
    }
}

private struct AgentKnowledgeView: View {
    @Bindable var model: AgentKnowledgeModel
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent Knowledge").font(.title2)
                Spacer()
                Button("Done", action: done)
            }
            Text("Project memory") .font(.headline)
            TextEditor(text: $model.memo).font(.body).frame(height: 110).border(.gray.opacity(0.3))
            Button("Save memo", action: model.saveMemo)
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project skills").font(.headline)
                    List(model.skills, selection: $model.selectedSkill) { skill in
                        Button {
                            model.select(skill.name)
                        } label: {
                            HStack {
                                Text(skill.name)
                                Spacer()
                                if skill.claude { Text("Claude").font(.caption2).foregroundStyle(.purple) }
                                if skill.codex { Text("Codex").font(.caption2).foregroundStyle(.cyan) }
                            }
                        }.buttonStyle(.plain)
                    }.frame(width: 250)
                    HStack {
                        TextField("new-skill-name", text: $model.newSkillName)
                        Button("Add", action: model.createSkill)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedSkill ?? "Select a skill").font(.headline)
                    TextEditor(text: $model.skillText).font(.system(size: 12, design: .monospaced))
                        .border(.gray.opacity(0.3))
                    HStack {
                        Button("Save skill", action: model.saveSkill).disabled(model.selectedSkill == nil)
                        Button("Share with Claude + Codex", action: model.shareSelectedWithBoth)
                            .disabled(model.selectedSkill == nil)
                    }
                }
            }
            Text(model.message).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 820, height: 620, alignment: .top).preferredColorScheme(.dark)
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
