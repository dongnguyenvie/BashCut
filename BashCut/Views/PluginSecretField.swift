import BashCutPlugin
import BashCutProject
import SwiftUI

/// A secret option (`PluginOptionField`): a password field with Save and Clear. A stored secret shows as dots with
/// "Saved"; with `check`, Save first asks the plugin and keeps a refused key out of the secret store unless the user
/// chooses Save Anyway.
struct PluginSecretField: View {
    /// The option's value: `{"set": true}` while one is stored; a string to save, empty to clear.
    @Binding var value: JSONValue
    /// Asks the plugin about a key before it is saved (nil when it could not answer).
    var check: ((String) async -> PluginOptionCheck?)?
    @State private var text = ""
    /// Whether a secret is stored, as this field last set it; nil until it saves or clears one (the binding's
    /// `{"set": …}` is read when the Settings row is drawn, so it lags a save).
    @State private var stored: Bool?
    @State private var checking = false
    @State private var verdict: PluginOptionCheck?

    private var secretIsSet: Bool { stored ?? (value.object["set"] == .bool(true)) }

    var body: some View {
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
}
