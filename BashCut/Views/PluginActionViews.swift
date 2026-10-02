import BashCutAutomation
import BashCutPlugin
import BashCutProject
import SwiftUI

/// Buttons for the plugin actions placed at `placement` (`toolbar`, `panel.media`, `inspector.color`…).
/// Draws nothing when no plugin contributes there.
struct PluginActionStrip: View {
    @Bindable var document: ProjectDocument
    let placement: String
    var compact = false

    var body: some View {
        let actions = document.plugins.actions(at: placement)
        if !actions.isEmpty {
            if compact {
                ForEach(actions) { action in
                    Button {
                        document.triggerPluginAction(action)
                    } label: {
                        Label(action.title, systemImage: action.spec.icon ?? "puzzlepiece.extension")
                    }
                    .disabled(!document.canRunPluginAction(action))
                    .help(action.plugin.manifest.name + ": " + action.title)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Label("Plugins", systemImage: "puzzlepiece.extension").font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(actions) { action in
                        Button {
                            document.triggerPluginAction(action)
                        } label: {
                            Label(action.title, systemImage: action.spec.icon ?? "puzzlepiece.extension")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(!document.canRunPluginAction(action))
                        .help(action.plugin.manifest.name)
                    }
                }
            }
        }
    }
}

/// Invisible buttons that bind plugin action shortcuts while the editor window is key.
struct PluginShortcutButtons: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        ZStack {
            ForEach(document.plugins.actions.filter { $0.shortcut?.keyboardShortcut != nil }) { action in
                if let shortcut = action.shortcut?.keyboardShortcut {
                    Button(action.title) { document.triggerPluginAction(action) }
                        .keyboardShortcut(shortcut)
                        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                }
            }
        }.frame(width: 0, height: 0)
    }
}

/// The native form for a plugin action's parameters, drawn from its declared options.
struct PluginActionParamsSheet: View {
    @Bindable var document: ProjectDocument
    @Bindable var model: PluginManagerModel

    var body: some View {
        if let pending = model.pendingAction {
            VStack(alignment: .leading, spacing: 14) {
                Label(pending.action.title, systemImage: pending.action.spec.icon ?? "puzzlepiece.extension")
                    .font(.title2)
                Text(pending.action.plugin.manifest.name).font(.caption).foregroundStyle(.secondary)
                if let confirm = pending.action.spec.confirm {
                    Text(confirm).foregroundStyle(.orange)
                }
                Form {
                    ForEach(pending.action.params) { option in
                        PluginOptionField(option: option, value: Binding(
                            get: { model.pendingAction?.values[option.id] ?? option.fallback },
                            set: { model.pendingAction?.values[option.id] = $0 }))
                    }
                }.formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Cancel") { model.pendingAction = nil }.keyboardShortcut(.cancelAction)
                    Button("Run") { document.runPendingPluginAction() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(width: 460).preferredColorScheme(.dark)
        }
    }
}

/// One option rendered natively: text field, picker, number field or toggle.
struct PluginOptionField: View {
    let option: PluginOption
    @Binding var value: JSONValue
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        let title = option.title(language: PluginText.language)
        VStack(alignment: .leading, spacing: 2) {
            switch option.type {
            case .bool:
                Toggle(title, isOn: Binding(get: { value == .bool(true) }, set: { value = .bool($0) }))
            case .enumeration:
                Picker(title, selection: Binding(get: { value.string ?? "" }, set: { value = .string($0) })) {
                    ForEach(option.choices ?? [], id: \.self) { Text($0).tag($0) }
                }
            case .string, .number, .integer:
                TextField(title, text: $text)
                    .onAppear { text = Self.text(value) }
                    .onChange(of: text) {
                        if let parsed = try? option.parse(text) {
                            value = parsed
                            invalid = false
                        } else {
                            invalid = true
                        }
                    }
                    .foregroundStyle(invalid ? Color.orange : Color.primary)
            }
            if let help = option.help { Text(help).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    static func text(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .integer(let number): String(number)
        case .number(let number): String(number)
        case .bool(let flag): flag ? "on" : "off"
        default: ""
        }
    }
}

/// Edits plugin hooks proposed while Settings keeps hook edits for review.
struct PluginProposalSheet: View {
    @Bindable var document: ProjectDocument
    @Bindable var model: PluginManagerModel

    var body: some View {
        if let proposal = model.proposals.first {
            VStack(alignment: .leading, spacing: 12) {
                Label("\(proposal.plugin.manifest.name) proposes an edit", systemImage: "puzzlepiece.extension")
                    .font(.title2)
                Text(proposal.title).font(.headline)
                Text("After \(proposal.event)").font(.caption).foregroundStyle(.secondary)
                if let message = proposal.proposal.message { Text(message) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(proposal.proposal.operations.enumerated()), id: \.offset) { _, operation in
                            Text(ProjectDocument.describe(operation)).font(.caption.monospaced()).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
                if model.proposals.count > 1 {
                    Text("\(model.proposals.count - 1) more waiting").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Discard") { resolve(proposal.id, apply: false) }.keyboardShortcut(.cancelAction)
                    Button("Apply") { resolve(proposal.id, apply: true) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(width: 520).preferredColorScheme(.dark)
        }
    }

    private func resolve(_ id: String, apply: Bool) {
        do { try document.resolvePluginProposal(id, apply: apply) } catch {
            document.message = error.localizedDescription
        }
    }
}
