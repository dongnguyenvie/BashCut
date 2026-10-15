import BashCutAgent
import SwiftUI

/// The agent dock's setup card: ① the BashCut skills for Claude Code and Codex on this Mac (what `agent setup` does)
/// and ② the editing tools (the starter plugin bundle, what `/bc:setup` installs), plus the shown chat agent's API
/// key. It opens the first time; Later (`agent.kit-later`) folds it into the dock header's Setup chip.
struct AgentSetupStepsView: View {
    @Bindable var model: AgentDockModel

    /// The chat agent shown in the dock, when its plugin reported that it is not ready (no API key).
    private var chatNeedingKey: ChatAgentModel? {
        guard model.pluginViewKey == nil, let id = model.chatPluginID else { return nil }
        let agent = model.document.chatAgents.model(for: id)
        guard let status = agent.status?.object, status["ready"] != .bool(true) else { return nil }
        return agent
    }

    var body: some View {
        let checklist = model.setupChecklist
        if model.showsSetupCard || chatNeedingKey != nil {
            VStack(alignment: .leading, spacing: 0) {
                header(checklist)
                if model.setupExpanded {
                    Divider().opacity(0.5)
                    if checklist.skills != .notApplicable { skillsStep(checklist) }
                    if checklist.tools != .notApplicable { toolsStep(checklist) }
                    if let agent = chatNeedingKey { keyRow(agent) }
                    footer
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.cyan.opacity(0.3)))
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    private func header(_ checklist: AgentSetupChecklist) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.setupExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.cyan).padding(.top, 1)
                // One line when the dock is wide enough; otherwise the count goes under the title.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        title
                        if checklist.total > 0 { Text("·").foregroundStyle(.secondary) }
                        count(checklist)
                    }
                    VStack(alignment: .leading, spacing: 2) { title; count(checklist) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 3)
                    .rotationEffect(.degrees(model.setupExpanded ? 180 : 0))
            }
            .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(model.setupExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private var title: some View {
        Text(String(format: String(localized: "Set up BashCut for %@"), model.setupAgentNames))
            .font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func count(_ checklist: AgentSetupChecklist) -> some View {
        if checklist.total > 0 {
            Text(String(format: String(localized: "%d of %d done"), checklist.done, checklist.total))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
        }
    }

    private func skillsStep(_ checklist: AgentSetupChecklist) -> some View {
        SetupStepRow(number: 1, done: checklist.skillsDone, title: "BashCut skills") {
            if model.kitSettingUp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Installing…").font(.caption).foregroundStyle(.secondary)
                }
            } else if case .installed(let version) = checklist.skills {
                Text("✓ v" + version).font(.caption.monospacedDigit()).foregroundStyle(.green)
            } else {
                Button(checklist.skills == .outdated ? "Update" : "Install skills") { model.setUpKitFromPrompt() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        } detail: {
            Text(String(
                format: String(localized: "%@ learns how to cut, caption, review and export in BashCut (~1 min)"),
                model.setupAgentNames))
            ForEach(model.restartSessions) { session in
                Button(String(format: String(localized: "Restart %@ tab"), session.title)) {
                    model.restartForKit(session)
                }
                .controlSize(.small)
                .help("The running agent loads the new skills only when it restarts; it continues the same conversation.")
            }
        }
    }

    private func toolsStep(_ checklist: AgentSetupChecklist) -> some View {
        let plugins = model.document.plugins
        let busy = plugins.installBusy
        return SetupStepRow(number: 2, done: checklist.toolsDone, title: "Editing tools") {
            if checklist.toolsDone {
                EmptyView()
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(checklist.tools == .needsSetup ? "Finish setup…" : "Install…") {
                    if checklist.tools == .needsSetup { model.showStarterSetup() } else { model.installStarterTools() }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        } detail: {
            let bytes = model.starterBytes
            let summary = String(localized: "Captions, Vietnamese voice, motion graphics, stock search")
            Text(bytes > 0 && !checklist.toolsDone
                ? String(format: String(localized: "%@ · about %@"), summary,
                         ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                : summary)
            if case .missing(let installed, let total) = checklist.tools, installed > 0 {
                Text(String(format: String(localized: "%d of %d plugins installed"), installed, total))
            } else if checklist.tools == .needsSetup {
                Text("A plugin still needs its setup (Plugins › Installed)")
            }
        }
    }

    private func keyRow(_ agent: ChatAgentModel) -> some View {
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

    private var footer: some View {
        HStack {
            Button("What's this?") { model.document.run(.showAgentKit) }.buttonStyle(.link)
            Spacer()
            if model.setupPending {
                Button("Later") { model.document.run(.dismissAgentKitPrompt) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.kitSettingUp)
            } else if model.setupFinishedHere {
                Button("Done") { model.closeFinishedSetup() }.buttonStyle(.borderless)
            }
        }
        .font(.caption).padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 8)
    }
}

/// One numbered step: ①/② (a check once done), its title and one line of why, and its action on the right.
private struct SetupStepRow<Action: View, Detail: View>: View {
    let number: Int
    let done: Bool
    let title: LocalizedStringKey
    @ViewBuilder let action: Action
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.85) : Color.cyan.opacity(0.18))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                } else {
                    Text("\(number)").font(.caption2.bold().monospacedDigit()).foregroundStyle(.cyan)
                }
            }
            .frame(width: 18, height: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                VStack(alignment: .leading, spacing: 4) { detail }
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            action
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }
}

/// The dock header's chip after Later: "Setup 1/2"; clicking it opens the card again (`agent.setup-show`).
struct AgentSetupChip: View {
    @Bindable var model: AgentDockModel

    var body: some View {
        let checklist = model.setupChecklist
        if model.setupPending && model.setupFolded {
            Button { model.document.run(.showAgentSetup) } label: {
                Text(String(format: String(localized: "Setup %d/%d"), checklist.done, max(checklist.total, 1)))
                    .font(.caption.monospacedDigit()).padding(.horizontal, 7).frame(height: 20)
                    .foregroundStyle(.cyan)
                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .help("Set up BashCut for the agent: skills and editing tools")
        }
    }
}
