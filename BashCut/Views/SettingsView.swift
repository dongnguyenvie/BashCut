import BashCutAgent
import BashCutDocument
import BashCutEngine
import SwiftUI

struct SettingsView: View {
    let model: AgentDockModel
    @Bindable var settings: SettingsModel
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
                Picker("Default agent", selection: $settings.defaultProviderRaw) {
                    ForEach(AgentProviders.agents, id: \.id) { Text($0.title).tag($0.id.rawValue) }
                }
                Toggle("Allow agent timeline edits", isOn: $settings.allowAgentEdits)
                LabeledContent("Agents outside BashCut") {
                    HStack {
                        Toggle("Allow", isOn: $settings.allowExternalAgents).labelsHidden()
                        Button("New token", action: model.applyExternalAgentPreference)
                            .disabled(!settings.allowExternalAgents)
                    }
                }
                Toggle("Run agent exports without confirmation", isOn: $settings.autoApprovePrivileged)
                Picker("Default export preset", selection: $settings.defaultExportPresetRaw) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(LocalizedStringKey(preset.title)).tag(preset.rawValue)
                    }
                }
                Picker("Interface language", selection: $settings.interfaceLanguage) {
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
        .onChange(of: settings.allowAgentEdits) { model.applyAgentEditPreference() }
        .onChange(of: settings.allowExternalAgents) { model.applyExternalAgentPreference() }
    }
}
