import AppKit
import BashCutAgent
import SwiftTerm
import SwiftUI

struct AgentDockView: View {
    @Bindable var model: AgentDockModel
    var detached = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AGENT").font(.caption.bold())
                Spacer()
                Button {
                    detached ? model.attach() : model.detach()
                } label: {
                    Image(systemName: detached ? "rectangle.portrait.and.arrow.forward" : "macwindow.on.rectangle")
                }
                .buttonStyle(.plain)
                .help(detached ? "Attach agent dock" : "Detach agent dock")
                Button {
                    model.knowledge.load(from: model.directory)
                    model.showKnowledge = true
                } label: {
                    Image(systemName: "books.vertical")
                }.buttonStyle(.plain).help("Skills and project memory")
                Menu {
                    ForEach(AgentProviders.all, id: \.id) { provider in
                        Button("\(provider.title) terminal") { model.open(provider.id) }
                    }
                    Button("Model API") { model.apiVisible = true }
                    Divider()
                    ForEach(AgentProviders.agents, id: \.id) { provider in
                        Button("Handoff to \(provider.title)") { model.handoff(to: provider.id) }
                    }
                } label: {
                    Image(systemName: "plus")
                }.menuStyle(.borderlessButton).frame(width: 24)
            }.padding(10)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.sessions) { session in
                        HStack(spacing: 3) {
                            Button(session.title) {
                                model.selectedSession = session.id
                                model.apiVisible = false
                            }
                            .tint(model.selectedSession == session.id && !model.apiVisible ? .cyan : .gray)
                            Button {
                                model.close(session)
                            } label: {
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("API") { model.apiVisible = true }
                }
            }.padding(.horizontal, 8)
            Divider()
            if model.apiVisible {
                apiPanel
            } else if let session = model.current {
                TerminalPanel(session: session).id(session.id)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "terminal").font(.largeTitle).foregroundStyle(.cyan)
                    Text("Choose an agent").font(.headline)
                    Text("Use your CLI login or connect a model API.").foregroundStyle(.secondary)
                    Button("Start default agent") { model.openDefault() }
                        .buttonStyle(.borderedProminent)
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
                    Button("Connect model API") { model.apiVisible = true }
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
                }.disabled(!model.apiVisible && model.current == nil)
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
                }.font(.caption).disabled(!model.apiVisible && model.current == nil)
            }.padding(10)
        }.background(Color(red: 0.045, green: 0.05, blue: 0.06))
            .sheet(isPresented: $model.showKnowledge) {
                AgentKnowledgeView(model: model.knowledge, done: { model.showKnowledge = false })
            }
    }
    private var apiPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: $model.configuration.kind) {
                    ForEach(ModelAdapters.all, id: \.kind) { Text($0.title).tag($0.kind) }
                }
                TextField("API base URL", text: $model.configuration.baseURL)
                TextField("Model ID", text: $model.configuration.model)
                SecureField("API key (Keychain)", text: $model.apiKey)
                Button("Save connection", action: model.saveConfiguration)
                Picker("Output", selection: $model.mode) {
                    Text("Script").tag("script")
                    Text("Timeline edit").tag("edit")
                }.pickerStyle(.segmented)
                if model.mode == "script" {
                    Picker("Language", selection: $model.scriptLanguage) {
                        Text("Python").tag("python")
                        Text("Shell").tag("shell")
                    }
                }
                TextEditor(text: $model.prompt).font(.body).frame(minHeight: 90).border(.gray.opacity(0.3))
                    .accessibilityLabel("Request to the model")
                Toggle("Include project context", isOn: $model.includeContext)
                if let image = model.contextImageURL {
                    HStack {
                        Label(image.lastPathComponent, systemImage: "photo")
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Button("Remove") { model.contextImageURL = nil }.controlSize(.small)
                    }
                }
                Text("Generate sends this request to the configured endpoint.").font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Generate", action: model.generate).disabled(model.generating)
                    if model.generating {
                        ProgressView().controlSize(.small)
                        Button("Cancel", action: model.cancel)
                    }
                }
                TextEditor(text: $model.output).font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 220).border(.gray.opacity(0.3)).accessibilityLabel(
                        "Review generated output")
                if model.outputMode == "edit" {
                    Button("Apply as one undo step", action: model.applyProposal)
                        .disabled(model.generating || model.output.isEmpty || model.requestRevision == nil)
                } else if model.outputMode == "script" {
                    HStack {
                        Button("Save script…", action: model.saveScript)
                        Button("Run reviewed script…", action: model.runScript)
                    }.disabled(model.generating || model.output.isEmpty)
                }
            }.textFieldStyle(.roundedBorder).padding(10)
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

private struct TerminalPanel: NSViewRepresentable {
    let session: TerminalSession
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.view }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}
