import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI
import UniformTypeIdentifiers

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
                    .help(action.plugin.manifest.displayName + ": " + action.title)
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
                        .help(action.plugin.manifest.displayName)
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
                Text(pending.action.plugin.manifest.displayName).font(.caption).foregroundStyle(.secondary)
                if let confirm = pending.action.spec.confirm {
                    Text(confirm.text).foregroundStyle(.orange)
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

/// One option rendered natively: text field, picker, number field, toggle or file chooser.
struct PluginOptionField: View {
    let option: PluginOption
    @Binding var value: JSONValue
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        let title = option.title.text
        VStack(alignment: .leading, spacing: 2) {
            switch option.type {
            case .bool:
                Toggle(title, isOn: Binding(get: { value == .bool(true) }, set: { value = .bool($0) }))
            case .enumeration:
                Picker(title, selection: Binding(get: { value.string ?? "" }, set: { value = .string($0) })) {
                    ForEach(option.choices ?? [], id: \.self) { Text(option.label(for: $0)).tag($0) }
                }
            case .file:
                // Stacked, so narrow panels (Voice, Text, Audio) keep the file name and both buttons readable.
                Text(title)
                Text(value.string.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
                    ?? String(localized: "None"))
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    .help(value.string ?? "")
                HStack(spacing: 6) {
                    Button("Choose…") { if let path = Self.chooseFile(option) { value = .string(path) } }
                        .fixedSize()
                    if value.string?.isEmpty == false {
                        Button("Clear File") { value = .string("") }.fixedSize()
                    }
                }.controlSize(.small)
            case .secret:
                Text(title)
                HStack(spacing: 6) {
                    SecureField(value.object["set"] == .bool(true) ? "Saved" : "Not set", text: $text)
                    Button("Save") {
                        value = .string(text)
                        text = ""
                    }.disabled(text.isEmpty).fixedSize()
                    if value.object["set"] == .bool(true) {
                        Button("Clear") { value = .string("") }.fixedSize()
                    }
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
            if let help = option.help { Text(help.text).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    /// Opens a file panel through `ModalCenter`, so agents can answer it with `ui respond --path`.
    static func chooseFile(_ option: PluginOption) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = option.help?.text ?? option.title.text
        if let types = option.fileTypes, !types.isEmpty {
            panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        }
        return ModalCenter.shared.open(panel, name: "plugin-option-file")?.first?.path
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
                Label("\(proposal.plugin.manifest.displayName) proposes an edit", systemImage: "puzzlepiece.extension")
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

/// Shown under a provider picker when no installed plugin provides `capability`: opens Plugins › Browse filtered
/// to providers of it.
struct FindPluginButton: View {
    @Bindable var document: ProjectDocument
    let capability: String

    var body: some View {
        if document.plugins.providers(for: capability).isEmpty {
            Button {
                document.showPluginBrowser(capability: capability)
            } label: {
                Label("Find a plugin…", systemImage: "puzzlepiece.extension")
            }.help(String(format: String(localized: "Browse plugins that provide %@"), capability))
        }
    }
}

/// The options of the plugin behind a provider picker (`providerID` empty means Automatic: the provider BashCut
/// would choose first), shown in the panel that uses it, such as the voice in the Voice panel.
struct ProviderOptionsView: View {
    @Bindable var document: ProjectDocument
    let capability: String
    let providerID: String

    private var plugin: InstalledPlugin? {
        let choices = document.plugins.providers(for: capability)
        let choice = providerID.isEmpty ? choices.first : choices.first { $0.provider.id == providerID }
        return choice.flatMap { document.plugins.plugin($0.pluginID) }
    }

    var body: some View {
        if let plugin, let options = plugin.manifest.options, !options.isEmpty {
            let values = document.pluginOptionValues(plugin)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(options) { option in
                    PluginOptionField(option: option, value: Binding(
                        get: { values[option.id] ?? option.fallback },
                        set: { value in
                            do {
                                try document.setPluginOption(plugin, option: option.id, value: value, author: .user)
                            } catch { document.message = error.localizedDescription }
                        }))
                }
            }.id(plugin.id)
        }
    }
}
