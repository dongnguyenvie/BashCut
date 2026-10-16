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
            ForEach(document.plugins.actions.filter {
                $0.shortcut?.keyboardShortcut != nil && !document.plugins.isHidden($0.plugin)
            }) { action in
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

/// Asks the user before a plugin action that declares `confirm` runs. The action's job waits meanwhile.
struct PluginConfirmSheet: View {
    let pending: PendingPluginConfirm
    let resolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(pending.action.title, systemImage: pending.action.spec.icon ?? "puzzlepiece.extension")
                .font(.title2)
            Text(pending.action.plugin.manifest.displayName).font(.caption).foregroundStyle(.secondary)
            if let confirm = pending.action.spec.confirm { Text(confirm.text).textSelection(.enabled) }
            if pending.author != .user {
                Text("Requested by \(pending.author.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { resolve(false) }.keyboardShortcut(.cancelAction)
                // No Return shortcut for an agent's request: a keystroke meant for a terminal must not run it.
                if pending.author == .user {
                    Button("Run") { resolve(true) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Run") { resolve(true) }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(20).frame(width: 460).interactiveDismissDisabled()
    }
}

/// One option rendered natively: text field, picker, number field, toggle or file chooser.
struct PluginOptionField: View {
    let option: PluginOption
    /// False when the caller shows the title and help itself (a Settings row); then pass `.labelsHidden()`.
    var showsTitle = true
    @Binding var value: JSONValue
    /// For a secret with `check`: asks the plugin about a key before it is saved (nil when it could not answer).
    var check: ((String) async -> PluginOptionCheck?)?
    @State private var text = ""
    @State private var invalid = false
    /// Whether a secret is stored, as this field last set it; nil until it saves or clears one (the binding's
    /// `{"set": …}` is read when the Settings row is drawn, so it lags a save).
    @State private var stored: Bool?
    @State private var checking = false
    @State private var verdict: PluginOptionCheck?

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
                if showsTitle { Text(title) }
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
                if showsTitle { Text(title) }
                secretField
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
            if showsTitle, let help = option.help { Text(help.text).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var secretIsSet: Bool { stored ?? (value.object["set"] == .bool(true)) }

    /// A password field with Save and Clear. A stored secret shows as dots with "Saved"; with `check`, Save first asks
    /// the plugin and keeps a refused key out of the Keychain unless the user chooses Save Anyway.
    @ViewBuilder private var secretField: some View {
        HStack(spacing: 6) {
            SecureField(secretIsSet ? "••••••••••••" : String(localized: "Not set"), text: $text)
                .onChange(of: text) { verdict = nil }
                .onSubmit { if !text.isEmpty, !checking { saveSecret() } }
            if checking { ProgressView().controlSize(.small) }
            Button(secretIsSet ? "Replace" : "Save") { saveSecret() }.disabled(text.isEmpty || checking).fixedSize()
            if secretIsSet {
                Button("Clear") {
                    value = .string("")
                    stored = false
                    verdict = nil
                }.fixedSize()
            }
        }
        if checking {
            Text("Checking the key…").font(.caption2).foregroundStyle(.secondary)
        } else if let verdict, !verdict.ok {
            HStack(spacing: 6) {
                Label(verdict.message ?? String(localized: "The plugin refused this key"), systemImage: "xmark.octagon.fill")
                    .font(.caption2).foregroundStyle(.red).lineLimit(3)
                Button("Save Anyway") { storeSecret(checked: nil) }.controlSize(.small).fixedSize()
            }
        } else if let verdict {
            Label(verdict.message ?? String(localized: "Saved and checked"), systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green).lineLimit(3)
        } else if secretIsSet {
            Label("Saved", systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func saveSecret() {
        guard let check else { return storeSecret(checked: nil) }
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        verdict = nil
        Task { @MainActor in
            let answer = await check(candidate)
            checking = false
            guard candidate == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if let answer, !answer.ok {
                verdict = answer
            } else {
                storeSecret(checked: answer ?? PluginOptionCheck(
                    ok: true, message: String(localized: "Saved; the plugin could not check it")))
            }
        }
    }

    private func storeSecret(checked: PluginOptionCheck?) {
        value = .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        text = ""
        stored = true
        verdict = checked
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
