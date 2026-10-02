import BashCutAgent
import BashCutEngine
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AgentDockModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done", action: done)
            }
            Form {
                LabeledContent("Workspace") {
                    HStack {
                        Text(model.directory.path).lineLimit(1).truncationMode(.middle)
                        Button("Change…", action: model.chooseWorkspace)
                    }
                }
                Picker("Default agent", selection: $model.defaultProviderRaw) {
                    Text("Claude").tag(TerminalProvider.claude.rawValue)
                    Text("Codex").tag(TerminalProvider.codex.rawValue)
                }
                Toggle("Allow agent timeline edits", isOn: $model.allowAgentEdits)
                Picker("Default export preset", selection: $model.defaultExportPresetRaw) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(LocalizedStringKey(preset.title)).tag(preset.rawValue)
                    }
                }
                Picker("Interface language", selection: $model.interfaceLanguage) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Tiếng Việt").tag("vi")
                }
            }.formStyle(.grouped)
            Text("Language changes apply after restarting BashCut.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Re-enable agent edits by starting a new Claude or Codex session.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 650)
        .onChange(of: model.defaultProviderRaw) { model.savePreferences() }
        .onChange(of: model.allowAgentEdits) { model.applyAgentEditPreference() }
        .onChange(of: model.defaultExportPresetRaw) { model.savePreferences() }
        .onChange(of: model.interfaceLanguage) { model.savePreferences() }
    }
}
