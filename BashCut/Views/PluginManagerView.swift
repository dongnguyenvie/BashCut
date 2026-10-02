import BashCutDocument
import BashCutPlugin
import SwiftUI

struct PluginManagerView: View {
    @Bindable var model: PluginManagerModel
    let document: ProjectDocument
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plugins").font(.title2)
                Spacer()
                Picker("View", selection: $model.tab) {
                    ForEach(PluginSheetTab.allCases) { tab in
                        Text(tab == .updates && !model.updates.isEmpty ? "\(tab.title) (\(model.updates.count))" : tab.title)
                            .tag(tab)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
                Button("Install Plugin…", action: model.choosePlugin).disabled(model.installing)
                    .help("Install a plugin folder from this Mac")
                Button("Done", action: done)
            }
            Text("Optional tools run outside the editor. A plugin runs only after you trust its exact files; "
                + "dependencies are installed only after you approve the exact plan.")
                .font(.caption).foregroundStyle(.secondary)
            switch model.tab {
            case .activity: hookLog
            case .browse: PluginBrowseView(model: model, updatesOnly: false)
            case .updates: PluginBrowseView(model: model, updatesOnly: true)
            case .installed: installed
            }
            if !model.diagnostics.isEmpty {
                DisclosureGroup("Diagnostics (\(model.diagnostics.count))") {
                    Text(model.diagnostics.joined(separator: "\n")).font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            if model.installing { ProgressView("Installing plugin dependencies…") }
            Text(model.message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 760, height: 620, alignment: .top).preferredColorScheme(.dark)
        .sheet(item: $model.pendingInstall) { pending in
            PluginInstallApprovalView(
                pending: pending, registry: model.registry, approve: model.installPendingPlugin,
                cancel: model.cancelPendingInstall)
        }
        .task(id: model.tab) {
            if model.tab == .browse || model.tab == .updates { await model.refreshRegistry() }
        }
    }

    @ViewBuilder private var installed: some View {
        if model.plugins.isEmpty {
            ContentUnavailableView {
                Label("No plugins installed", systemImage: "puzzlepiece.extension")
            } actions: {
                Button("Browse Plugins") { model.tab = .browse }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.plugins) { plugin in
                PluginRow(model: model, document: document, plugin: plugin)
            }
        }
    }

    private var hookLog: some View {
        List(model.hookLog.reversed()) { run in
            HStack(alignment: .firstTextBaseline) {
                Text(run.date, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(run.event).font(.caption.monospaced())
                Text(run.pluginID).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(run.outcome.rawValue).font(.caption.bold())
                    .foregroundStyle(run.outcome == .failed || run.outcome == .dropped ? Color.orange : Color.secondary)
            }
            .help(run.detail)
        }
        .overlay {
            if model.hookLog.isEmpty {
                ContentUnavailableView("No hook activity yet", systemImage: "bolt.horizontal")
            }
        }
    }
}

private struct PluginRow: View {
    @Bindable var model: PluginManagerModel
    let document: ProjectDocument
    let plugin: InstalledPlugin
    @State private var showOptions = false

    private var availability: PluginAvailability { model.availability[plugin.id] ?? .untrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(plugin.manifest.displayName).font(.headline)
                Text("v" + plugin.manifest.version).foregroundStyle(.secondary)
                if plugin.manifest.transportKind == .session {
                    Text("session").font(.caption2.monospaced()).padding(.horizontal, 4)
                        .background(.white.opacity(0.08)).cornerRadius(3)
                }
                Spacer()
                stateBadge
            }
            Text(plugin.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
            if !plugin.manifest.capabilities.isEmpty {
                Text(plugin.manifest.capabilities.joined(separator: " · ")).font(.caption.monospaced())
            }
            if !plugin.manifest.actions.isEmpty {
                Text("Actions: " + plugin.manifest.actions.map { $0.title.text }
                    .joined(separator: ", ")).font(.caption)
            }
            if !plugin.manifest.hooks.isEmpty {
                Text("Hooks: " + plugin.manifest.hooks.map { $0.event + ($0.proposesEdits ? " (edits)" : "") }
                    .joined(separator: ", ")).font(.caption)
            }
            if !plugin.manifest.dependencies.isEmpty {
                Text("Dependencies: " + plugin.manifest.dependencies.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let health = model.health[plugin.id], !health.dependencies.isEmpty {
                ForEach(health.dependencies) { dependency in
                    Text("\(dependency.name): \(dependency.detail)")
                        .font(.caption2)
                        .foregroundStyle(dependency.state == .available ? Color.secondary : Color.orange)
                }
            }
            if availability != .ready {
                Text(availability.detail).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if availability == .untrusted || availability == .changed {
                    Button("Trust") { model.trustPlugin(plugin) }
                        .help("Allow this plugin to run. Its manifest and entrypoint are pinned; a change asks again.")
                } else if !model.trust.isBundled(plugin), model.trust.grant(for: plugin.id) != nil {
                    Button("Revoke Trust") { model.revokeTrust(plugin) }
                }
                Toggle("Enabled", isOn: Binding(
                    get: { model.isEnabled(plugin) },
                    set: { value in
                        do { try model.setEnabled(plugin, enabled: value) } catch { model.message = error.localizedDescription }
                    }))
                if !plugin.manifest.hooks.isEmpty {
                    Toggle("Hooks", isOn: Binding(
                        get: { model.trust.hooksEnabled(plugin.id) },
                        set: { value in
                            do { try model.setEnabled(plugin, hooks: value) } catch { model.message = error.localizedDescription }
                        }))
                }
                if !(plugin.manifest.options ?? []).isEmpty {
                    Button(showOptions ? "Hide Options" : "Options…") { showOptions.toggle() }
                }
                Spacer()
                if model.isRemovable(plugin) {
                    Button("Remove", role: .destructive, action: remove)
                }
                Button(model.checking.contains(plugin.id) ? "Checking…" : "Check Health") {
                    model.checkHealth(plugin)
                }.disabled(model.checking.contains(plugin.id))
            }.font(.caption)
            if showOptions { options }
        }.padding(.vertical, 4)
    }

    private func remove() {
        let choice = ModalCenter.shared.alert(
            "plugin-remove", title: String(format: String(localized: "Remove %@?"), plugin.manifest.displayName),
            message: String(localized: "Its files, trust and settings on this Mac are removed. Projects keep their plugin data."),
            buttons: [ModalOption("cancel", String(localized: "Cancel")), ModalOption("remove", String(localized: "Remove"))])
        guard choice == "remove" else { return }
        do { try model.removePlugin(plugin) } catch { model.message = error.localizedDescription }
    }

    private var stateBadge: some View {
        let ready = availability == .ready && model.health[plugin.id].map { $0.state == .ready } ?? true
        let text = availability == .ready
            ? (model.health[plugin.id].map { $0.state == .ready ? "Ready" : "Needs setup" } ?? "Enabled")
            : availability.name.capitalized
        return Label(text, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(ready ? Color.green : Color.orange)
    }

    private var options: some View {
        let values = document.pluginOptionValues(plugin)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(plugin.manifest.options ?? []) { option in
                HStack(alignment: .top) {
                    PluginOptionField(option: option, value: Binding(
                        get: { values[option.id] ?? option.fallback },
                        set: { value in
                            do {
                                try document.setPluginOption(plugin, option: option.id, value: value, author: .user)
                            } catch { model.message = error.localizedDescription }
                        }))
                    Text(option.effectiveScope == .project ? "project" : "this Mac")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(8).background(.white.opacity(0.04)).cornerRadius(6)
    }
}

private struct PluginInstallApprovalView: View {
    let pending: PendingPluginInstall
    let registry: PluginRegistryDocument?
    let approve: () -> Void
    let cancel: () -> Void
    private var plugin: InstalledPlugin { pending.plugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                String(format: String(localized: pending.replacing ? "Update %@?" : "Install %@?"), plugin.manifest.displayName),
                systemImage: "puzzlepiece.extension"
            ).font(.title2)
            if let archive = pending.archive { download(archive) }
            if !plugin.manifest.capabilities.isEmpty {
                Text("Capabilities: " + plugin.manifest.capabilities.joined(separator: ", "))
            }
            if !plugin.manifest.actions.isEmpty {
                Text("Adds: " + plugin.manifest.actions.map { $0.title.text }.joined(separator: ", "))
            }
            if !plugin.manifest.hooks.isEmpty {
                Text("Listens to: " + plugin.manifest.hooks.map(\.event).joined(separator: ", "))
            }
            if plugin.manifest.dependencies.isEmpty {
                Text("This plugin has no external dependencies.")
            } else {
                Text("Dependency plan").font(.headline)
                ForEach(plugin.manifest.dependencies) { dependency in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dependency.name).bold()
                        Text(dependency.install?.summary ?? "Manual installation required")
                        if let command = dependency.install?.command {
                            Text(([command.executable] + command.arguments).joined(separator: " "))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }.padding(8).background(.white.opacity(0.04)).cornerRadius(6)
                }
            }
            Text("Installing trusts these exact files. The plugin and listed dependency commands run with your user "
                + "permissions; plugin edits are validated and undoable.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(pending.replacing ? "Update" : "Install", action: approve).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 560).preferredColorScheme(.dark)
    }

    private func download(_ archive: StagedPluginArchive) -> some View {
        let publisher = archive.entry.publisher.flatMap { registry?.publishers[$0] }
        return VStack(alignment: .leading, spacing: 3) {
            Text("From the plugin registry").font(.headline)
            Text("Version \(archive.version.version)" + (publisher.map { " · " + $0.name.text } ?? "")
                + (publisher?.verified == true ? " ✓" : ""))
            Text(archive.version.url).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Text("SHA-256 " + archive.version.sha256).font(.caption2.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Checksum verified. Archive signatures are not checked yet.").font(.caption2).foregroundStyle(.secondary)
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04)).cornerRadius(6)
    }
}
