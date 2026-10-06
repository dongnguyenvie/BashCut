import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import SwiftUI

/// Settings › Plugins: hook and update preferences, then the options of every installed plugin that declares
/// some (the same values as Plugins › Options… and `plugins option`), grouped by category, one collapsible plugin
/// at a time.
struct SettingsPluginsSection: View {
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    let done: () -> Void
    @State private var error = ""
    @State private var filter = ""
    @State private var expanded: Set<String> = []
    @Environment(\.settingsQuery) private var query

    private var withOptions: [InstalledPlugin] {
        document.plugins.plugins.filter { !($0.manifest.options ?? []).isEmpty }
    }

    /// The filter field narrows the list; while searching Settings, the search does instead.
    private var configurable: [InstalledPlugin] {
        guard query.isEmpty, !filter.isEmpty else { return withOptions }
        return withOptions.filter { plugin in
            plugin.manifest.displayName.localizedCaseInsensitiveContains(filter)
                || plugin.id.localizedCaseInsensitiveContains(filter)
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
        SettingsSection("Plugins") {
            SettingsRow("Run plugin hooks", keywords: ["hook", "event"]) {
                SettingsSwitch(isOn: $settings.runPluginHooks)
            }
            SettingsRow("Apply plugin hook edits without review", keywords: ["hook", "proposal", "review"]) {
                SettingsSwitch(isOn: $settings.autoApplyPluginHookEdits).disabled(!settings.runPluginHooks)
            }
            if PluginChannel.current.allowsUserPlugins {
                SettingsRow("Check for plugin updates daily", keywords: ["update", "version"]) {
                    SettingsSwitch(isOn: $settings.checkPluginUpdatesDaily)
                }
            }
        } accessory: {
            if PluginChannel.current.allowsUserPlugins {
                Button("Add Plugin…") { openPlugins(thenAdd: true) }.buttonStyle(.link)
            }
            Button("Manage Plugins…") { openPlugins(thenAdd: false) }.buttonStyle(.link)
        }
        if withOptions.count > 1 {
            TextField("Filter plugins", text: $filter, prompt: Text("Filter plugins"))
                .textFieldStyle(.roundedBorder).labelsHidden().padding(.bottom, 12)
                .settingsHiddenWhileSearching()
        }
        if configurable.isEmpty {
            SettingsSection {
                SettingsPlainRow {
                    Text(filter.isEmpty ? LocalizedStringKey("No installed plugin has options.") : "No plugins match")
                        .foregroundStyle(.secondary)
                }
                .settingsHiddenWhileSearching()
            }
        }
        ForEach(PluginSection.byCategory(configurable, category: document.plugins.category(of:))) { group in
            SettingsSection(verbatim: group.title, symbol: group.symbol) {
                ForEach(group.items) { plugin in
                    SettingsDisclosureRow(terms: terms(plugin), isExpanded: isExpanded(plugin)) {
                        options(plugin)
                    } label: {
                        HStack {
                            Text(plugin.manifest.displayName)
                            Text("v" + plugin.manifest.version).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if !error.isEmpty {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
    }

    /// The plugin's name and ID and every option's title and help, so a search for an option finds its plugin.
    private func terms(_ plugin: InstalledPlugin) -> [String] {
        [plugin.manifest.displayName, plugin.id] + (plugin.manifest.options ?? []).flatMap { option in
            [option.title.text, option.help?.text ?? ""]
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
        let all = plugin.manifest.options ?? []
        return ForEach(all) { option in
            SettingsRow(verbatim: option.title.text, detail: option.help?.text) {
                HStack(spacing: 8) {
                    PluginOptionField(option: option, showsTitle: false, value: Binding(
                        get: { values[option.id] ?? option.fallback },
                        set: { value in
                            do {
                                try document.setPluginOption(plugin, option: option.id, value: value, author: .user)
                                error = ""
                            } catch { self.error = error.localizedDescription }
                        }))
                        .labelsHidden().toggleStyle(.switch).frame(maxWidth: 360, alignment: .trailing)
                    Text(PluginOptionPolicy.scope(of: option, in: all) == .project ? "project" : "this Mac")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
