import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutPlugins
import SwiftUI

/// Settings, one section at a time from the sidebar. The section is `document.ui.settingsSection`, so agents can
/// open it with `ui view --settings-section`.
struct SettingsView: View {
    let model: AgentDockModel
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    let done: () -> Void

    private var section: String { document.ui.settingsSection }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done", action: done)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                Form { detail }.formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 820, height: 600)
        .onChange(of: settings.allowAgentEdits) { model.applyAgentEditPreference() }
        .onChange(of: settings.allowExternalAgents) { model.applyExternalAgentPreference() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(UIAction.settingsSections, id: \.self) { name in
                Button {
                    document.ui.settingsSection = name
                } label: {
                    Label(LocalizedStringKey(Self.title(name)), systemImage: Self.icon(name))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(section == name ? Color.accentColor.opacity(0.25) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(section == name ? Color.primary : Color.secondary)
            }
            Spacer()
        }.padding(10).frame(width: 180)
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case "agents": agents
        case "plugins": SettingsPluginsSection(document: document, settings: settings, done: done)
        case "storage": StorageSettingsView(document: document)
        default: general
        }
    }

    @ViewBuilder private var general: some View {
        Section {
            LabeledContent("Workspace") {
                HStack {
                    Text(model.directory.path).lineLimit(1).truncationMode(.middle)
                    Button("Change…", action: model.chooseWorkspace)
                }
            }
            LabeledContent("Projects folder") {
                HStack {
                    Text(NewProjectView.displayPath(settings.defaultProjectsFolder)).lineLimit(1).truncationMode(.middle)
                        .help(settings.defaultProjectsFolder.path)
                    Button("Change…", action: chooseProjectsFolder)
                    if settings.projectsFolder != nil {
                        Button("Reset") { settings.projectsFolder = nil }
                            .help("Use ~/Movies/BashCut again")
                    }
                }
            }
            Picker("Default export preset", selection: $settings.defaultExportPresetRaw) {
                ForEach(ExportPreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.title)).tag(preset.rawValue)
                }
            }
        }
        Section {
            Picker("Interface language", selection: $settings.interfaceLanguage) {
                Text("System").tag("system")
                Text("English").tag("en")
                Text("Tiếng Việt").tag("vi")
            }
        } footer: {
            Text("Language changes apply after restarting BashCut.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var agents: some View {
        Section {
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
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Re-enable agent edits by starting a new Claude or Codex session.")
                Text("With confirmation off, agents can export and write files without asking. Every request is still logged.")
                Text("Agents outside BashCut use the bashcut CLI or MCP with a token file only your user account can read.")
            }.font(.caption).foregroundStyle(.secondary)
        }
        AgentSettingsView(document: document, settings: settings)
    }

    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.defaultProjectsFolder
        guard let url = ModalCenter.shared.open(panel, name: "choose-projects-folder")?.first else { return }
        settings.rememberProjectsFolder(url)
    }

    static func title(_ section: String) -> String {
        switch section {
        case "agents": "Agents"
        case "plugins": "Plugins"
        case "storage": "Storage"
        default: "General"
        }
    }

    static func icon(_ section: String) -> String {
        switch section {
        case "agents": "terminal"
        case "plugins": "puzzlepiece.extension"
        case "storage": "internaldrive"
        default: "gearshape"
        }
    }
}

/// Settings › Plugins: hook and update preferences, then the options of every installed plugin that declares
/// some (the same values as Plugins › Options… and `plugins option`).
private struct SettingsPluginsSection: View {
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    let done: () -> Void
    @State private var error = ""

    private var configurable: [InstalledPlugin] {
        document.plugins.plugins.filter { !($0.manifest.options ?? []).isEmpty }
    }

    var body: some View {
        Section {
            Toggle("Run plugin hooks", isOn: $settings.runPluginHooks)
            Toggle("Apply plugin hook edits without review", isOn: $settings.autoApplyPluginHookEdits)
                .disabled(!settings.runPluginHooks)
            if PluginChannel.current.allowsUserPlugins {
                Toggle("Check for plugin updates daily", isOn: $settings.checkPluginUpdatesDaily)
            }
        } header: {
            HStack {
                Text("Plugins")
                Spacer()
                Button("Manage Plugins…") {
                    done()
                    // Present the Plugins sheet once Settings has closed.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        document.ui.showPlugins = true
                    }
                }.buttonStyle(.link)
            }
        }
        if configurable.isEmpty {
            Section {
                Text("No installed plugin has options.").foregroundStyle(.secondary)
            }
        }
        ForEach(configurable) { plugin in
            let values = document.pluginOptionValues(plugin)
            Section {
                ForEach(plugin.manifest.options ?? []) { option in
                    HStack(alignment: .top) {
                        PluginOptionField(option: option, value: Binding(
                            get: { values[option.id] ?? option.fallback },
                            set: { value in
                                do {
                                    try document.setPluginOption(plugin, option: option.id, value: value, author: .user)
                                    error = ""
                                } catch { self.error = error.localizedDescription }
                            }))
                        Text(PluginOptionPolicy.scope(of: option, in: plugin.manifest.options ?? []) == .project ? "project" : "this Mac")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text(plugin.manifest.displayName)
                    Text("v" + plugin.manifest.version).foregroundStyle(.secondary)
                }
            }
        }
        if !error.isEmpty {
            Section { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
