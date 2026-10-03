import BashCutDocument
import BashCutPlugin
import BashCutPlugins
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
                    ForEach(PluginSheetTab.visible) { tab in
                        Text(tab == .updates && !model.updates.isEmpty ? "\(tab.title) (\(model.updates.count))" : tab.title)
                            .tag(tab)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
                if PluginChannel.current.allowsUserPlugins {
                    Button("Install Plugin…", action: model.choosePlugin).disabled(model.installing)
                        .help("Install a plugin folder from this Mac")
                }
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
            if model.installing { PluginInstallProgressView(model: model) }
            Text(model.message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 760, height: 620, alignment: .top).preferredColorScheme(.dark)
        .sheet(item: $model.pendingInstall) { pending in
            PluginInstallApprovalView(
                pending: pending, registry: model.registry, required: model.requiredBytes(pending),
                blocker: model.installBlocker(pending), approve: model.installPendingPlugin,
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
                if PluginChannel.current.allowsUserPlugins { Button("Browse Plugins") { model.tab = .browse } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.plugins) { plugin in
                PluginRow(model: model, document: document, plugin: plugin)
            }
            .task {
                // Probe dependencies once so missing ones offer Install Dependencies….
                for plugin in model.plugins where model.health[plugin.id] == nil && !plugin.manifest.dependencies.isEmpty {
                    await model.checkHealthNow(plugin)
                }
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
            if let reason = model.yankedReason(plugin) {
                Label(String(format: String(localized: "Your version was withdrawn: %@"), reason),
                      systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
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
                    HStack(spacing: 6) {
                        Text(dependency.name).font(.caption2)
                        PluginDependencyBadge(
                            state: dependency.state,
                            installable: plugin.manifest.dependencies.first { $0.id == dependency.id }?.install != nil,
                            checking: false)
                    }.help(dependency.detail)
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
                if needsSetup {
                    Button("Install Dependencies…") { model.requestSetup(plugin) }.disabled(model.installing)
                        .help("Run this plugin's install recipes again (after a failed or cancelled setup)")
                }
                if model.isRemovable(plugin) {
                    Button("Remove", role: .destructive, action: remove).disabled(model.installing)
                }
                Button(model.checking.contains(plugin.id) ? "Checking…" : "Check Health") {
                    model.checkHealth(plugin)
                }.disabled(model.checking.contains(plugin.id))
            }.font(.caption)
            if showOptions { options }
        }.padding(.vertical, 4)
    }

    /// A dependency is missing and has an install recipe.
    private var needsSetup: Bool {
        guard let health = model.health[plugin.id] else { return false }
        return health.dependencies.contains { status in
            status.state != .available && plugin.manifest.dependencies.contains { $0.id == status.id && $0.install != nil }
        }
    }

    private func remove() {
        let usage = PluginFolders.usage(plugin.id)
        var buttons = [ModalOption("cancel", String(localized: "Cancel")), ModalOption("remove", String(localized: "Remove"))]
        if usage > 0 {
            buttons.append(ModalOption("remove-data", String(
                format: String(localized: "Remove with Data (%@)"),
                ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))))
        }
        var text = String(localized: "Its files, trust and settings on this Mac are removed. Projects keep their plugin data.")
        if usage > 0 {
            text += "\n\n" + String(
                localized: "Its downloaded data (environments, models) can be kept for a later reinstall or removed too.")
        }
        let choice = ModalCenter.shared.alert(
            "plugin-remove", title: String(format: String(localized: "Remove %@?"), plugin.manifest.displayName),
            message: text, buttons: buttons)
        guard choice == "remove" || choice == "remove-data" else { return }
        do { try model.removePlugin(plugin, deleteData: choice == "remove-data") } catch { model.message = error.localizedDescription }
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
    let required: Int64
    let blocker: String?
    let approve: () -> Void
    let cancel: () -> Void
    private var plugin: InstalledPlugin { pending.plugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                String(
                    format: String(localized: pending.repair ? "Set up %@?" : pending.replacing ? "Update %@?" : "Install %@?"),
                    plugin.manifest.displayName),
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
                    let state = pending.preflight?.dependencies.first { $0.id == dependency.id }?.state
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(dependency.name).bold()
                            Spacer()
                            PluginDependencyBadge(state: state, installable: dependency.install != nil,
                                                  checking: pending.preflight == nil)
                        }
                        Text(([dependency.probe.executable] + dependency.probe.arguments).joined(separator: " "))
                            .font(.caption.monospaced()).textSelection(.enabled)
                        if state != .available, let install = dependency.install {
                            Text(install.summary)
                            Text(([install.command.executable] + install.command.arguments).joined(separator: " "))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }.padding(8).background(.white.opacity(0.04)).cornerRadius(6)
                }
            }
            if required > 0 {
                let free = PluginFolders.availableBytes()
                Text(String(
                    format: String(localized: "Downloads and disk: about %@ (%@ free)"),
                    ByteCountFormatter.string(fromByteCount: required, countStyle: .file),
                    free.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"))
                    .font(.caption)
            }
            if let blocker { Label(blocker, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange) }
            Text("Installing trusts these exact files. The plugin and listed dependency commands run with your user "
                + "permissions; plugin edits are validated and undoable.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(pending.repair ? "Set Up" : pending.replacing ? "Update" : "Install", action: approve)
                    .buttonStyle(.borderedProminent).disabled(blocker != nil)
            }
        }.padding(20).frame(width: 560).preferredColorScheme(.dark)
    }

    private func download(_ archive: StagedPluginArchive) -> some View {
        let publisher = archive.entry.publisher.flatMap { registry?.publishers[$0] }
        return VStack(alignment: .leading, spacing: 3) {
            Text("From the plugin registry").font(.headline)
            Text("Version \(archive.version.version)" + (publisher.map { " · " + $0.name.text } ?? ""))
            PluginSignatureBadge(trust: archive.publisherTrust)
            Text(archive.version.url).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Text("SHA-256 " + archive.version.sha256).font(.caption2.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04)).cornerRadius(6)
    }
}

/// Install or setup progress: the current step, a bar when the recipe reports `::progress`, Cancel and the output.
private struct PluginInstallProgressView: View {
    @Bindable var model: PluginManagerModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let progress = model.installProgress {
                    ProgressView(value: progress) { Text(model.installStep).font(.caption) }
                } else {
                    ProgressView { Text(model.installStep).font(.caption) }.progressViewStyle(.linear)
                }
                Button("Cancel", role: .cancel, action: model.cancelInstall).disabled(model.installJob == nil)
            }
            if let last = model.installLog.last {
                Text(last).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if !model.installLog.isEmpty {
                DisclosureGroup("Output", isExpanded: $showLog) {
                    ScrollView {
                        Text(model.installLog.suffix(200).joined(separator: "\n")).font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(height: 120)
                }.font(.caption)
            }
        }.padding(8).background(.white.opacity(0.04)).cornerRadius(6)
    }
}

/// A dependency's state in words people understand: available, installed by setup, or not possible on this Mac.
private struct PluginDependencyBadge: View {
    let state: PluginDependencyStatus.State?
    let installable: Bool
    let checking: Bool

    var body: some View {
        if checking {
            Label("Checking…", systemImage: "hourglass").font(.caption2).foregroundStyle(.secondary)
        } else {
            switch state {
            case .notChecked?:
                Label("Checked after approval", systemImage: "lock").font(.caption2).foregroundStyle(.secondary)
            case .available?:
                Label("Available on this Mac", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
            case .missing?, nil where installable:
                Label("Installed during setup", systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary)
            default:
                Label("Not available on this Mac", systemImage: "xmark.octagon.fill").font(.caption2).foregroundStyle(.orange)
                    .help("The plugin needs it but cannot install it; ask the plugin's author.")
            }
        }
    }
}

/// Who signed a registry archive: BashCut, a publisher the registry lists, or nobody.
struct PluginSignatureBadge: View {
    let trust: PluginPublisherTrust

    var body: some View {
        switch trust {
        case .firstParty:
            Label("Signed by BashCut", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.cyan)
        case .verifiedPublisher(let publisher):
            Label(String(format: String(localized: "Signed by %@"), publisher), systemImage: "checkmark.seal")
                .font(.caption).foregroundStyle(.green)
        case .unsigned:
            Label("Not signed: only the checksum is verified. Install it only if you trust where it comes from.",
                  systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(.orange)
        }
    }
}
