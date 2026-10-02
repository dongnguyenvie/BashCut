import BashCutPlugin
import SwiftUI

struct PluginManagerView: View {
    @Bindable var model: PluginManagerModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plugins").font(.title2)
                Spacer()
                Button("Install Plugin…", action: model.choosePlugin).disabled(model.installing)
                Button("Done", action: done)
            }
            Text("Optional tools run outside the editor. Dependencies are installed only after you approve the exact plan.")
                .font(.caption).foregroundStyle(.secondary)
            if model.plugins.isEmpty {
                ContentUnavailableView("No plugins installed", systemImage: "puzzlepiece.extension")
            } else {
                List(model.plugins) { plugin in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(plugin.manifest.name).font(.headline)
                            Spacer()
                            if let health = model.health[plugin.id] {
                                Label(
                                    health.state == .ready ? "Ready" : "Needs setup",
                                    systemImage: health.state == .ready
                                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(
                                        health.state == .ready ? Color.green : Color.orange)
                            }
                            Text("v" + plugin.manifest.version).foregroundStyle(.secondary)
                        }
                        Text(plugin.manifest.capabilities.joined(separator: " · ")).font(.caption.monospaced())
                        if !plugin.manifest.dependencies.isEmpty {
                            Text("Dependencies: " + plugin.manifest.dependencies.map(\.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let health = model.health[plugin.id], !health.dependencies.isEmpty {
                            ForEach(health.dependencies) { dependency in
                                Text("\(dependency.name): \(dependency.detail)")
                                    .font(.caption2)
                                    .foregroundStyle(
                                        dependency.state == .available
                                            ? Color.secondary : Color.orange)
                            }
                        }
                        Button(
                            model.checking.contains(plugin.id) ? "Checking…" : "Check Health"
                        ) {
                            model.checkHealth(plugin)
                        }.disabled(model.checking.contains(plugin.id))
                    }.padding(.vertical, 4)
                }
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
        .padding(20).frame(width: 680, height: 500).preferredColorScheme(.dark)
        .sheet(item: $model.pendingInstall) { pending in
            PluginInstallApprovalView(
                plugin: pending.plugin, approve: model.installPendingPlugin,
                cancel: { model.pendingInstall = nil })
        }
    }
}

private struct PluginInstallApprovalView: View {
    let plugin: InstalledPlugin
    let approve: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Install \(plugin.manifest.name)?", systemImage: "puzzlepiece.extension")
                .font(.title2)
            Text("Capabilities: " + plugin.manifest.capabilities.joined(separator: ", "))
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
            Text("The plugin and listed dependency commands run with your user permissions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Install", action: approve).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 560).preferredColorScheme(.dark)
    }
}
