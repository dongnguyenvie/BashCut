import AppKit
import BashCutDocument
import SwiftUI

/// Settings › Storage: one row per plugin with its total (largest first; expand for code, data and downloads),
/// then the shared plugin runtimes, the registry copy, preview proxies and the rest, with Clear for what can be made or downloaded again.
struct StorageSettingsView: View {
    let document: ProjectDocument
    @State private var entries: [StorageEntry]?
    @State private var clearing: String?
    @State private var confirm: StorageEntry?
    @State private var error = ""

    var body: some View {
        Section {
            if let entries {
                ForEach(StorageUsage.byPlugin(entries)) { plugin in
                    RowDisclosureGroup {
                        ForEach(plugin.entries) { entry in row(entry) }
                    } label: {
                        pluginLabel(plugin)
                    }
                }
                ForEach(entries.filter { $0.pluginID == nil }) { entry in row(entry) }
                LabeledContent("Total") {
                    Text(Self.bytes(entries.reduce(0) { $0 + $1.bytes })).monospacedDigit().bold()
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
        } header: {
            HStack {
                Text("Storage")
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([StorageUsage.supportFolder]) }
                    .buttonStyle(.link)
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Measure again")
            }
        }
        .task { await load() }
        .confirmationDialog(
            confirm.map(confirmTitle) ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
            presenting: confirm
        ) { entry in
            Button("Delete", role: .destructive) { clear(entry) }
        } message: { entry in
            switch entry.kind {
            case .pluginData:
                Text("The plugin's environments and settings are deleted. Use Install Dependencies… in Plugins to set it up again.")
            case .sharedData:
                Text("Runtimes shared by plugins are deleted. Plugins that use them must be set up again with Install Dependencies… in Plugins.")
            default:
                Text("This is downloaded or made again when needed.")
            }
        }
    }

    private func row(_ entry: StorageEntry) -> some View {
        LabeledContent {
            HStack {
                Text(Self.bytes(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
                if entry.clearable {
                    if clearing == entry.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(Self.setsUpAgain(entry) ? LocalizedStringKey("Delete…") : LocalizedStringKey("Free Up")) {
                            if Self.confirms(entry) { confirm = entry } else { clear(entry) }
                        }.disabled(entry.bytes == 0 || clearing != nil)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title(entry))
                Text(entry.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func pluginLabel(_ plugin: PluginStorage) -> some View {
        LabeledContent {
            Text(Self.bytes(plugin.bytes)).monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(pluginName(plugin.pluginID))
                if !plugin.installed {
                    Text("Not installed — left over from a removed plugin").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pluginName(_ id: String) -> String { document.plugins.plugin(id)?.manifest.displayName ?? id }

    private func title(_ entry: StorageEntry) -> String {
        let plugin = entry.pluginID.map(pluginName) ?? ""
        switch entry.kind {
        case .plugins: return String(format: String(localized: "%@ — plugin"), plugin)
        case .pluginData: return String(format: String(localized: "%@ — data"), plugin)
        case .pluginCache: return String(format: String(localized: "%@ — downloads"), plugin)
        case .sharedData: return String(localized: "Shared plugin runtimes")
        case .sharedCache: return String(localized: "Shared plugin downloads")
        case .registry: return String(localized: "Plugin catalog copy")
        case .proxies: return String(localized: "Preview proxies (this project)")
        case .rampAudio: return String(localized: "Speed ramp audio (this project)")
        case .audit: return String(localized: "Automation audit log")
        }
    }

    /// Deleting it means setting plugins up again.
    private static func setsUpAgain(_ entry: StorageEntry) -> Bool { entry.kind == .pluginData || entry.kind == .sharedData }

    private static func confirms(_ entry: StorageEntry) -> Bool {
        [.pluginData, .pluginCache, .sharedData, .sharedCache].contains(entry.kind)
    }

    private func confirmTitle(_ entry: StorageEntry) -> String {
        String(format: String(localized: "Delete %@ (%@)?"), title(entry), Self.bytes(entry.bytes))
    }

    private func clear(_ entry: StorageEntry) {
        clearing = entry.id
        error = ""
        Task {
            do { try await document.clearStorage(entry) } catch { self.error = error.localizedDescription }
            clearing = nil
            await load()
        }
    }

    private func load() async { entries = await document.storageEntries() }

    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
