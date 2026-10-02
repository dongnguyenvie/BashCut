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
                    ForEach(AgentProviders.agents, id: \.id) { Text($0.title).tag($0.id.rawValue) }
                }
                Toggle("Allow agent timeline edits", isOn: $model.allowAgentEdits)
                LabeledContent("Agents outside BashCut") {
                    HStack {
                        Toggle("Allow", isOn: $model.allowExternalAgents).labelsHidden()
                        Button("New token", action: model.applyExternalAgentPreference)
                            .disabled(!model.allowExternalAgents)
                    }
                }
                Toggle("Run agent exports without confirmation", isOn: $model.autoApprovePrivileged)
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
            Text("With confirmation off, agents can export and write files without asking. Every request is still logged.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Agents outside BashCut use the bashcut CLI or MCP with a token file only your user account can read.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 650)
        .onChange(of: model.defaultProviderRaw) { model.savePreferences() }
        .onChange(of: model.allowAgentEdits) { model.applyAgentEditPreference() }
        .onChange(of: model.allowExternalAgents) { model.applyExternalAgentPreference() }
        .onChange(of: model.autoApprovePrivileged) { model.savePreferences() }
        .onChange(of: model.defaultExportPresetRaw) { model.savePreferences() }
        .onChange(of: model.interfaceLanguage) { model.savePreferences() }
    }
}
