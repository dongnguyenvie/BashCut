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

    /// Large like an editor tab: the main window less a margin, measured when Settings opens.
    @State private var size = Self.preferredSize()

    static func preferredSize() -> CGSize {
        let window = NSApp.mainWindow?.contentLayoutRect.size ?? CGSize(width: 1280, height: 800)
        return CGSize(width: min(max(window.width - 80, 820), 1400), height: min(max(window.height - 80, 600), 1000))
    }

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
        .frame(width: size.width, height: size.height)
        .onChange(of: settings.agentsCanEdit) { model.applyAgentEditPreference() }
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
        Section {
            LabeledContent("Version") {
                HStack {
                    Text(verbatim: "\(document.appUpdate.version) (\(document.appUpdate.build))").textSelection(.enabled)
                    Button("Check for Updates…") {
                        done()
                        // Present Software Update once Settings has closed.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            document.run(.showUpdates)
                        }
                    }
                }
            }
            if document.appUpdate.install.checksForUpdates {
                Toggle("Check for BashCut updates daily", isOn: $settings.checkAppUpdatesDaily)
            }
        } header: {
            Text("Updates")
        }
    }

    @ViewBuilder private var agents: some View {
        Section {
            Picker("Default agent", selection: $settings.defaultProviderRaw) {
                ForEach(AgentProviders.agents, id: \.id) { Text($0.title).tag($0.id.rawValue) }
            }
            LabeledContent("Agents outside BashCut") {
                HStack {
                    Toggle("Allow", isOn: $settings.allowExternalAgents).labelsHidden()
                    Button("New token", action: model.applyExternalAgentPreference)
                        .disabled(!settings.allowExternalAgents)
                }
            }
        } footer: {
            Text("Agents outside BashCut use the bashcut CLI or MCP with a token file only your user account can read.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        agentPermissions
        AgentSettingsView(document: document, settings: settings)
    }

    /// What agents may do without asking. Allow everything overrides the rest while it is on.
    @ViewBuilder private var agentPermissions: some View {
        let all = settings.dangerouslyAllowAgents
        Section {
            Toggle("Allow agent timeline edits", isOn: all ? .constant(true) : $settings.allowAgentEdits)
                .disabled(all)
            Toggle("Approve agent actions without asking", isOn: all ? .constant(true) : $settings.autoApprovePrivileged)
                .disabled(all)
            Picker(
                "Edits outside the attached clips",
                selection: all ? .constant(AgentScopeMode.off.rawValue) : $settings.agentScopeModeRaw
            ) {
                Text("Ask first").tag(AgentScopeMode.ask.rawValue)
                Text("Block").tag(AgentScopeMode.block.rawValue)
                Text("Allow").tag(AgentScopeMode.off.rawValue)
            }
            .disabled(all)
            Toggle(isOn: Binding(get: { all }, set: { setDangerouslyAllowAgents($0) })) {
                Label("Dangerously allow all agent actions", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(all ? .red : .primary)
            }
        } header: {
            Text("Agent permissions")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Re-enable agent edits by starting a new Claude or Codex session.")
                // swiftlint:disable:next line_length
                Text("Agent actions that ask first: exports, agent kit setup and updates, library items and preferences for every project. Every request is still logged.")
                Text("When you send clips to an agent, its edits to other clips or to the whole project ask you first, are blocked, or are allowed.")
                if all {
                    // swiftlint:disable:next line_length
                    Text("All agent actions run without asking, including plugin actions that normally ask first. Only installing and trusting plugins still needs you.")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Turning Allow everything on asks once; turning it off does not.
    private func setDangerouslyAllowAgents(_ on: Bool) {
        guard on else {
            settings.dangerouslyAllowAgents = false
            return
        }
        let choice = ModalCenter.shared.alert(
            "dangerously-allow-agents", title: String(localized: "Let agents do everything without asking?"),
            // swiftlint:disable:next line_length
            message: String(localized: "Agents can edit any clip, export, change the agent kit, save library items and preferences for every project, and run plugin actions without asking you. Every request is still logged."),
            buttons: [
                ModalOption("cancel", String(localized: "Cancel")),
                ModalOption("allow", String(localized: "Allow Everything")),
            ],
            style: .critical, userOnly: true)
        settings.dangerouslyAllowAgents = choice == "allow"
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
/// some (the same values as Plugins › Options… and `plugins option`), grouped by category, one collapsible plugin
/// at a time.
private struct SettingsPluginsSection: View {
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    let done: () -> Void
    @State private var error = ""
    @State private var filter = ""
    @State private var expanded: Set<String> = []

    private var configurable: [InstalledPlugin] {
        document.plugins.plugins.filter { plugin in
            !(plugin.manifest.options ?? []).isEmpty
                && (filter.isEmpty || plugin.manifest.displayName.localizedCaseInsensitiveContains(filter)
                    || plugin.id.localizedCaseInsensitiveContains(filter))
        }
    }

    /// Presents the Plugins sheet once Settings has closed; with `thenAdd`, Add Plugin… opens over it.
    private func openPlugins(thenAdd: Bool) {
        done()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            document.plugins.tab = .installed
            document.ui.showPlugins = true
            guard thenAdd else { return }
            try? await Task.sleep(for: .milliseconds(350))
            document.plugins.addPlugin()
        }
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
                if PluginChannel.current.allowsUserPlugins {
                    Button("Add Plugin…") { openPlugins(thenAdd: true) }.buttonStyle(.link)
                }
                Button("Manage Plugins…") { openPlugins(thenAdd: false) }.buttonStyle(.link)
            }
        }
        if document.plugins.plugins.filter({ !($0.manifest.options ?? []).isEmpty }).count > 1 {
            Section {
                TextField("Filter plugins", text: $filter, prompt: Text("Filter plugins")).labelsHidden()
            }
        }
        if configurable.isEmpty {
            Section {
                Text(filter.isEmpty ? LocalizedStringKey("No installed plugin has options.") : "No plugins match").foregroundStyle(.secondary)
            }
        }
        ForEach(PluginSection.byCategory(configurable, category: document.plugins.category(of:))) { group in
            Section {
                ForEach(group.items) { plugin in
                    RowDisclosureGroup(isExpanded: isExpanded(plugin)) {
                        options(plugin)
                    } label: {
                        HStack {
                            Text(plugin.manifest.displayName)
                            Text("v" + plugin.manifest.version).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label(group.title, systemImage: group.symbol)
            }
        }
        if !error.isEmpty {
            Section { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }

    /// Collapsed by default, unless it is the only plugin shown.
    private func isExpanded(_ plugin: InstalledPlugin) -> Binding<Bool> {
        Binding(
            get: { configurable.count == 1 || expanded.contains(plugin.id) },
            set: { open in
                if open { expanded.insert(plugin.id) } else { expanded.remove(plugin.id) }
            })
    }

    private func options(_ plugin: InstalledPlugin) -> some View {
        let values = document.pluginOptionValues(plugin)
        return ForEach(plugin.manifest.options ?? []) { option in
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
    }
}
