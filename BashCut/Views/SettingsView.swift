import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import SwiftUI

/// Settings, one section at a time from the sidebar, or every matching setting while the search box has text.
/// The section is `document.ui.settingsSection` and the search `document.ui.settingsSearch`, so agents can drive
/// both with `ui view --settings-section` and `--settings-search`.
struct SettingsView: View {
    let model: AgentDockModel
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    let done: () -> Void

    private var section: String { document.ui.settingsSection }
    private var query: String { document.ui.settingsSearch.trimmingCharacters(in: .whitespaces) }

    /// Large like an editor tab: the main window less a margin, measured when Settings opens.
    @State private var size = Self.preferredSize()
    /// Matching rows per section while searching.
    @State private var hits: [String: Int] = [:]

    /// Content stops widening here, so lines stay readable on a large window.
    static let maxContentWidth: CGFloat = 1000

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
                VStack(spacing: 0) {
                    searchField
                    ScrollView {
                        content
                            .environment(\.settingsQuery, query)
                            .frame(maxWidth: Self.maxContentWidth, alignment: .leading)
                            .padding(.horizontal, 24).padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: settings.agentsCanEdit) { model.applyAgentEditPreference() }
        .onChange(of: settings.allowExternalAgents) { model.applyExternalAgentPreference() }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search settings", text: Binding(
                get: { document.ui.settingsSearch }, set: { document.ui.settingsSearch = $0 }
            ))
            .textFieldStyle(.plain)
            if !document.ui.settingsSearch.isEmpty {
                Button {
                    document.ui.settingsSearch = ""
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: Self.maxContentWidth)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    /// One section, or while searching every section with matches under its title.
    @ViewBuilder private var content: some View {
        if query.isEmpty {
            VStack(alignment: .leading, spacing: 0) { page(section) }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(UIAction.settingsSections, id: \.self) { name in
                    SettingsSearchPage(id: name, title: Self.title(name), icon: Self.icon(name)) { page(name) }
                }
                if hits.values.reduce(0, +) == 0 {
                    Text("No settings match “\(query)”").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .onPreferenceChange(SettingsPageHits.self) { hits = $0 }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(UIAction.settingsSections, id: \.self) { name in
                sidebarItem(name)
            }
            Spacer()
        }.padding(10).frame(width: 180)
    }

    /// While searching, sections with matches show their count and the rest are dimmed; a click leaves the search.
    private func sidebarItem(_ name: String) -> some View {
        let searching = !query.isEmpty
        let count = hits[name] ?? 0
        let current = searching ? count > 0 : section == name
        return Button {
            document.ui.settingsSearch = ""
            document.ui.settingsSection = name
        } label: {
            HStack {
                Label(LocalizedStringKey(Self.title(name)), systemImage: Self.icon(name))
                Spacer()
                if searching, count > 0 {
                    Text(verbatim: "\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(current ? Color.accentColor.opacity(searching ? 0.15 : 0.25) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(current ? Color.primary : Color.secondary)
    }

    @ViewBuilder private func page(_ name: String) -> some View {
        switch name {
        case "agents": agents
        case "plugins": SettingsPluginsSection(document: document, settings: settings, done: done)
        case "storage": StorageSettingsView(document: document)
        default: general
        }
    }

    @ViewBuilder private var general: some View {
        SettingsSection {
            SettingsRow("Workspace", keywords: ["folder", "agent", "terminal"]) {
                Text(model.directory.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button("Change…", action: model.chooseWorkspace)
            }
            SettingsRow("Projects folder", keywords: ["folder", "new project", "Movies"]) {
                Text(NewProjectView.displayPath(settings.defaultProjectsFolder)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary).help(settings.defaultProjectsFolder.path)
                Button("Change…", action: chooseProjectsFolder)
                if settings.projectsFolder != nil {
                    Button("Reset") { settings.projectsFolder = nil }
                        .help("Use ~/Movies/BashCut again")
                }
            }
            SettingsRow("Default export preset", keywords: ["export", "TikTok", "YouTube"]) {
                Picker("Default export preset", selection: $settings.defaultExportPresetRaw) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(LocalizedStringKey(preset.title)).tag(preset.rawValue)
                    }
                }.labelsHidden().fixedSize()
            }
        }
        SettingsSection {
            SettingsRow("Interface language", keywords: ["English", "Tiếng Việt", "Vietnamese"]) {
                Picker("Interface language", selection: $settings.interfaceLanguage) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Tiếng Việt").tag("vi")
                }.labelsHidden().fixedSize()
            }
        } footer: {
            Text("Language changes apply after restarting BashCut.")
        }
        SettingsSection("Updates") {
            SettingsRow("Version", keywords: ["update", "BashCut"]) {
                Text(verbatim: "\(document.appUpdate.version) (\(document.appUpdate.build))").textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Button("Check for Updates…") {
                    done()
                    // Present Software Update once Settings has closed.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        document.run(.showUpdates)
                    }
                }
            }
            if document.appUpdate.install.checksForUpdates {
                SettingsRow("Check for BashCut updates daily", keywords: ["update"]) {
                    SettingsSwitch(isOn: $settings.checkAppUpdatesDaily)
                }
            }
        }
    }

    @ViewBuilder private var agents: some View {
        SettingsSection {
            SettingsRow("Default agent", keywords: ["Claude", "Codex"]) {
                Picker("Default agent", selection: $settings.defaultProviderRaw) {
                    ForEach(AgentProviders.agents, id: \.id) { Text($0.title).tag($0.id.rawValue) }
                }.labelsHidden().fixedSize()
            }
            SettingsRow("Agents outside BashCut", keywords: ["token", "CLI", "MCP", "external"]) {
                Button("New token", action: model.applyExternalAgentPreference)
                    .disabled(!settings.allowExternalAgents)
                SettingsSwitch(isOn: $settings.allowExternalAgents)
            }
        } footer: {
            Text("Agents outside BashCut use the bashcut CLI or MCP with a token file only your user account can read.")
        }
        agentPermissions
        AgentSettingsView(document: document, settings: settings)
    }

    /// What agents may do without asking. Allow everything overrides the rest while it is on.
    @ViewBuilder private var agentPermissions: some View {
        let all = settings.dangerouslyAllowAgents
        SettingsSection("Agent permissions") {
            SettingsRow("Allow agent timeline edits", keywords: ["edit", "token", "permission"]) {
                SettingsSwitch(isOn: all ? .constant(true) : $settings.allowAgentEdits).disabled(all)
            }
            SettingsRow("Approve agent actions without asking", keywords: ["approval", "export", "kit", "permission"]) {
                SettingsSwitch(isOn: all ? .constant(true) : $settings.autoApprovePrivileged).disabled(all)
            }
            SettingsRow("Edits outside the attached clips", keywords: ["scope", "guard", "Send to Agent", "permission"]) {
                Picker(
                    "Edits outside the attached clips",
                    selection: all ? .constant(AgentScopeMode.off.rawValue) : $settings.agentScopeModeRaw
                ) {
                    Text("Ask first").tag(AgentScopeMode.ask.rawValue)
                    Text("Block").tag(AgentScopeMode.block.rawValue)
                    Text("Allow").tag(AgentScopeMode.off.rawValue)
                }
                .labelsHidden().fixedSize().disabled(all)
            }
            SettingsRow(
                "Dangerously allow all agent actions", keywords: ["allow all", "scope", "permission"],
                symbol: "exclamationmark.triangle.fill", tint: all ? .red : nil
            ) {
                SettingsSwitch(isOn: Binding(get: { all }, set: { setDangerouslyAllowAgents($0) }))
            }
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
