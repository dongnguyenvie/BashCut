import BashCutPlugin
import SwiftUI

/// Browse's Recommended card: a bundle with the plugins this Mac does not have yet, installed after one approval.
struct PluginBundleCard: View {
    @Bindable var model: PluginManagerModel
    let bundle: PluginRegistryBundle

    var body: some View {
        let offered = model.members(of: bundle).filter(\.installable)
        let bytes = offered.reduce(Int64(0)) { total, member in
            total + Int64((member.listing?.version?.size ?? 0) + (member.listing?.version?.downloadBytes ?? 0))
        }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text(bundle.name.text).font(.headline)
                if let summary = bundle.summary { Text(summary.text).font(.caption) }
                Text(offered.map(\.name).joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                if bytes > 0 {
                    Text(String(format: String(localized: "Up to about %@ with every plugin checked"),
                                ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if offered.contains(where: { model.downloading.contains($0.id) }) {
                ProgressView().controlSize(.small)
            } else {
                Button("Install…") {
                    Task {
                        do { try await model.requestBundle(bundle.id) } catch { model.message = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(model.installing)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.cyan.opacity(0.25)))
    }
}

/// One approval for a bundle: every downloaded plugin with a checkbox, what it adds and sets up, the total size,
/// and the plugins left out with why. Installing trusts the checked plugins' exact files, like single installs.
struct PluginBundleApprovalView: View {
    @Binding var pending: PendingBundleInstall
    let registry: PluginRegistryDocument?
    let required: Int64
    let blocker: String?
    let approve: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(format: String(localized: "Install %@?"), pending.bundle.name.text), systemImage: "sparkles")
                .font(.title2)
            if let summary = pending.bundle.summary { Text(summary.text) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($pending.items) { $item in row($item) }
                    ForEach(pending.skipped) { skipped in
                        HStack {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                            Text(skipped.name)
                            Spacer()
                            Text(skipped.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(8).opacity(0.6)
                    }
                }
            }.frame(maxHeight: 420)
            if required > 0 {
                let free = PluginFolders.availableBytes()
                Text(String(
                    format: String(localized: "Downloads and disk: about %@ (%@ free)"),
                    ByteCountFormatter.string(fromByteCount: required, countStyle: .file),
                    free.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"))
                    .font(.caption)
            }
            if let blocker { Label(blocker, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            Text("""
                Installing trusts the checked plugins' exact files and runs their setup one after another. The plugins \
                and their setup commands run with your user permissions; plugin edits are validated and undoable.
                """)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(String(format: String(localized: "Install (%d)"), pending.selected.count), action: approve)
                    .buttonStyle(.borderedProminent).disabled(blocker != nil)
            }
        }.padding(20).frame(width: 620).preferredColorScheme(.dark)
    }

    private func row(_ item: Binding<PendingBundleInstall.Item>) -> some View {
        let plugin = item.wrappedValue.pending.plugin
        let archive = item.wrappedValue.pending.archive
        let manifest = plugin.manifest
        let setup = manifest.dependencies.filter { $0.install != nil }
        let setupBytes = setup.compactMap(\.estimatedBytes).reduce(0, +)
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: item.selected).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(manifest.displayName).bold()
                    Text("v" + manifest.version).foregroundStyle(.secondary)
                    if let archive { PluginSignatureBadge(trust: archive.publisherTrust) }
                }
                if let summary = archive?.entry.summary { Text(summary.text).font(.caption) }
                if !manifest.capabilities.isEmpty {
                    Text("Capabilities: \(manifest.capabilities.joined(separator: ", "))").font(.caption2)
                }
                if !manifest.skills.isEmpty {
                    Text("Teaches agents: \(PluginManagerView.skillNames(plugin))").font(.caption2)
                }
                if !setup.isEmpty {
                    Text("Sets up: \(setup.map { $0.install?.summary ?? $0.name }.joined(separator: "; "))").font(.caption2)
                }
                HStack(spacing: 8) {
                    if let size = archive?.version.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if setupBytes > 0 {
                        Text(String(format: String(localized: "+ %@ setup"), ByteCountFormatter.string(fromByteCount: setupBytes, countStyle: .file)))
                    }
                    Text(plugin.id).font(.caption2.monospaced())
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8).background(.white.opacity(0.04)).cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { item.wrappedValue.selected.toggle() }
    }
}
