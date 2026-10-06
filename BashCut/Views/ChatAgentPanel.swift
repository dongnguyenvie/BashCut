import BashCutAgent
import BashCutDocument
import BashCutProject
import SwiftUI

/// A chat agent's tab: the conversation with the plugin's agent, an input box, and its status. Every control has a
/// `chat` command (send, stop, reset, transcript, status).
struct ChatAgentPanel: View {
    let agent: ChatAgentModel
    let document: ProjectDocument
    /// The highlighted row of the slash-command menu.
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if agent.entries.isEmpty {
                            Text("Ask the agent to edit: it reads the timeline, makes undoable changes and checks the picture.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                        }
                        ForEach(agent.entries) { entry in
                            ChatEntryView(entry: entry, fps: document.project.fps).id(entry.id)
                        }
                        if agent.running {
                            ProgressView().controlSize(.small).id("running")
                        }
                        if let command = agent.runningCommand {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(String(format: String(localized: "Running %@…"), command))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(10)
                }
                .onChange(of: agent.entries.last?.text) {
                    if let last = agent.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            input
        }
        .task(id: agent.pluginID) { await agent.refreshStatus() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: statusReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(statusReady ? Color.green : Color.orange).font(.caption)
            Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Settings…") {
                document.ui.settingsSection = "plugins"
                document.ui.showSettings = true
            }.buttonStyle(.link).font(.caption)
            Button {
                Task { await agent.reset() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless).help("New conversation").disabled(agent.running)
        }.padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var input: some View {
        @Bindable var agent = agent
        return VStack(alignment: .leading, spacing: 6) {
            if let image = agent.draftImage {
                HStack {
                    Label(image.lastPathComponent, systemImage: "photo").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Remove") { agent.draftImage = nil }.controlSize(.small)
                }
            }
            if !agent.scope.isEmpty { scopeChips }
            if !suggestions.isEmpty { suggestionMenu }
            ZStack(alignment: .topLeading) {
                ChatInputView(text: $agent.draft, placeholder: String(localized: "Message to the agent"), onKey: key)
                if agent.draft.isEmpty {
                    Text("Message, or / for commands. Shift+Enter for a new line.")
                        .foregroundStyle(.tertiary).padding(.leading, 7).padding(.top, 4).allowsHitTesting(false)
                }
            }
            .frame(minHeight: 54, maxHeight: 120).padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
            HStack {
                if !agent.error.isEmpty {
                    Text(agent.error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
                Spacer()
                if agent.running {
                    Button("Stop", action: agent.stop)
                } else {
                    Button("Send", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(agent.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || agent.runningCommand != nil)
                }
            }
        }.padding(10)
        .onChange(of: agent.draft) { selection = 0 }
    }

    // MARK: Scope

    /// The clips attached with Send to Agent: every message carries them until removed.
    private var scopeChips: some View {
        HStack(alignment: .top, spacing: 6) {
            ScopeChipsView(items: agent.scope, fps: document.project.fps) { removed in
                agent.scope.removeAll { $0.id == removed.id }
            }
            if agent.scope.count > 1 {
                Button("Clear") { agent.scope = [] }.buttonStyle(.link).font(.caption)
            }
        }
        .help("The agent edits only these clips and asks before changing anything else.")
    }

    // MARK: Slash commands

    private struct Suggestion: Identifiable {
        let completion: String
        let title: String
        let detail: String
        /// Runs at once when chosen with Enter (a command that takes no arguments).
        let runs: Bool
        var id: String { completion }
    }

    /// Commands matching what is typed after `/`, or the argument choices of the command being typed.
    private var suggestions: [Suggestion] {
        let draft = agent.draft
        guard draft.hasPrefix("/"), !draft.contains("\n") else { return [] }
        let body = draft.dropFirst()
        if let space = body.firstIndex(of: " ") {
            let name = body[..<space].lowercased()
            let typed = body[body.index(after: space)...].lowercased()
            guard let command = agent.commands.first(where: { $0.name == name }), !typed.contains(" ") else { return [] }
            return command.choices.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }.prefix(8).map {
                Suggestion(completion: "/\(name) \($0)", title: $0, detail: command.summary, runs: true)
            }
        }
        let typed = body.lowercased()
        return agent.commands.filter { $0.name.hasPrefix(typed) || (typed.count > 1 && $0.name.contains(typed)) }
            .prefix(10).map { command in
                Suggestion(
                    completion: "/" + command.name + (command.args == nil ? "" : " "),
                    title: "/" + command.name + (command.args.map { " " + $0 } ?? ""), detail: command.summary,
                    runs: command.args == nil)
            }
    }

    private var suggestionMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                HStack {
                    Text(suggestion.title).font(.callout.monospaced()).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(suggestion.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(index == selection ? Color.accentColor.opacity(0.3) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { accept(suggestion, run: false) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1)))
    }

    /// Keys from the input: the menu takes arrows, Tab, Enter and Escape while it shows.
    private func key(_ key: ChatInputKey) -> Bool {
        let shown = suggestions
        if !shown.isEmpty {
            menuKey(key, shown)
            return true
        }
        switch key {
        case .submit:
            submit()
            return true
        case .escape:
            if agent.running { agent.stop() }
            return agent.running
        default: return false
        }
    }

    private func menuKey(_ key: ChatInputKey, _ shown: [Suggestion]) {
        let chosen = shown[min(selection, shown.count - 1)]
        switch key {
        case .up: selection = (selection - 1 + shown.count) % shown.count
        case .down: selection = (selection + 1) % shown.count
        case .tab: accept(chosen, run: false)
        // Enter on a command typed in full runs it; otherwise it completes the highlighted one.
        case .submit:
            if agent.draft.trimmingCharacters(in: .whitespaces) == chosen.completion && chosen.runs {
                submit()
            } else {
                accept(chosen, run: true)
            }
        case .escape: agent.draft = ""
        }
    }

    private func accept(_ suggestion: Suggestion, run: Bool) {
        agent.draft = suggestion.completion
        if run && suggestion.runs { submit() }
    }

    private func submit() {
        let text = agent.draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if agent.isCommand(text) {
            agent.draft = ""
            Task {
                do { try await agent.runCommand(text) } catch { agent.error = error.localizedDescription }
            }
            return
        }
        guard !agent.running, agent.runningCommand == nil else { return }
        let image = agent.draftImage
        agent.draft = ""
        agent.draftImage = nil
        agent.error = ""
        agent.send(text, imageURL: image)
    }

    private var statusReady: Bool { agent.status?.object["ready"] == .bool(true) }

    private var statusText: String {
        guard let status = agent.status?.object else { return String(localized: "Checking…") }
        if status["ready"] == .bool(true) {
            return [status["provider"]?.string, status["model"]?.string].compactMap { $0 }.joined(separator: " · ")
        }
        return status["detail"]?.string ?? String(localized: "Add an API key in Settings › Plugins")
    }
}

/// Attached timeline items as chips (`Clip · Main · 00:12–00:18`); `remove` adds an × to each.
struct ScopeChipsView: View {
    let items: [AgentScopeItem]
    let fps: FrameRate
    var remove: ((AgentScopeItem) -> Void)?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 3) {
                    Image(systemName: "film").font(.caption2)
                    Text(AgentScope.label(item, fps: fps)).font(.caption).lineLimit(1).truncationMode(.middle)
                    if let remove {
                        Button {
                            remove(item)
                        } label: {
                            Image(systemName: "xmark").font(.caption2.bold())
                        }
                        .buttonStyle(.borderless).help("Remove from the request")
                        .accessibilityLabel(String(format: String(localized: "Remove %@"), item.name))
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                .help(item.id)
            }
        }
    }
}

private struct ChatEntryView: View {
    let entry: ChatAgentModel.Entry
    let fps: FrameRate

    var body: some View {
        switch entry.kind {
        case .user:
            HStack {
                Spacer(minLength: 30)
                VStack(alignment: .trailing, spacing: 4) {
                    if let scope = entry.scope { ScopeChipsView(items: scope, fps: fps) }
                    Text(entry.text).textSelection(.enabled)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.18)))
            }
        case .assistant:
            Text(LocalizedStringKey(entry.text)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: entry.ok == nil ? "gearshape" : entry.ok == true ? "checkmark" : "xmark")
                    .foregroundStyle(entry.ok == false ? Color.orange : Color.secondary)
                Text(entry.name ?? "").font(.caption.monospaced())
                Text(entry.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        case .notice:
            Text(entry.text).font(.caption).foregroundStyle(.secondary)
        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }
}
