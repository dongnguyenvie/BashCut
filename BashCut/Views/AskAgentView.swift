import SwiftUI

/// Writes a request for the open agent: pick a template, fill in the parts in [brackets], send it.
struct AskAgentView: View {
    @Bindable var document: ProjectDocument
    @Bindable var ask: AgentAskModel
    @FocusState private var editing: Bool

    init(document: ProjectDocument) {
        self.document = document
        ask = document.agents.askModel
    }

    private var agents: AgentDockModel { document.agents }
    private var agentTitle: String? {
        if let id = agents.chatPluginID { return document.chatAgents.model(for: id).title }
        return agents.current?.title
    }
    private var isEmpty: Bool { ask.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask agent").font(.title2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                templates
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $ask.draft)
                        .font(.body).focused($editing)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topLeading) {
                            if ask.draft.isEmpty {
                                Text("What should the agent do? Pick a template or write your own.")
                                    .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                    Text("Fill in the parts in [brackets], then send.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Toggle("Attach current frame", isOn: $ask.attachFrame)
                Spacer()
                Button("Clear") {
                    ask.draft = ""
                    editing = true
                }.disabled(ask.draft.isEmpty)
                Button("Cancel") { document.ui.showAsk = false }.keyboardShortcut(.cancelAction)
                Button(ask.sending ? String(localized: "Preparing frame…") : String(localized: "Send")) {
                    Task { await agents.sendAsk() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty || ask.sending || !agents.hasOpenAgent)
            }
        }
        .padding(20).frame(width: 640, height: 400)
        .onAppear { editing = true }
    }

    private var subtitle: String {
        let count = document.selectedIDs.count
        let target = count > 1
            ? String(format: String(localized: "%d selected clips"), count)
            : document.selectedID ?? String(localized: "Whole project")
        guard let agentTitle else { return String(localized: "Open an agent in the dock first, then ask again") }
        return String(format: String(localized: "To %@ · about %@ · ⌘↩ sends"), agentTitle, target)
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Templates").font(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(AgentRequestTemplate.all) { template in
                Button {
                    ask.draft = template.text
                    editing = true
                } label: {
                    Label(template.title, systemImage: template.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).padding(.vertical, 4).padding(.horizontal, 6)
                .help(template.text)
            }
            Spacer()
        }.frame(width: 160)
    }
}
