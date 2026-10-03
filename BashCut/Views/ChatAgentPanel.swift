import BashCutDocument
import SwiftUI

/// A chat agent's tab: the conversation with the plugin's agent, an input box, and its status. Every control has a
/// `chat` command (send, stop, reset, transcript, status).
struct ChatAgentPanel: View {
    let agent: ChatAgentModel
    let document: ProjectDocument

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
                            ChatEntryView(entry: entry).id(entry.id)
                        }
                        if agent.running {
                            ProgressView().controlSize(.small).id("running")
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
            TextEditor(text: $agent.draft)
                .font(.body).frame(minHeight: 54, maxHeight: 120)
                .scrollContentBackground(.hidden).padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                .accessibilityLabel("Message to the agent")
            HStack {
                if !agent.error.isEmpty {
                    Text(agent.error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
                Spacer()
                if agent.running {
                    Button("Stop", action: agent.stop)
                } else {
                    Button("Send", action: send)
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(agent.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(10)
    }

    private func send() {
        let text = agent.draft
        let image = agent.draftImage
        agent.draft = ""
        agent.draftImage = nil
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

private struct ChatEntryView: View {
    let entry: ChatAgentModel.Entry

    var body: some View {
        switch entry.kind {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(entry.text).textSelection(.enabled).padding(8)
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
