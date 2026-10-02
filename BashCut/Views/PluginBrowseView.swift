import BashCutPlugin
import SwiftUI

/// Plugins › Browse and Updates: the registry, searched and filtered, with Install and Update.
struct PluginBrowseView: View {
    @Bindable var model: PluginManagerModel
    let updatesOnly: Bool
    @State private var query = ""

    private var listings: [PluginListing] {
        updatesOnly ? model.updates : model.listings(query: query, capability: model.browseCapability)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !updatesOnly {
                    TextField("Search plugins…", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    if let capability = model.browseCapability {
                        Button {
                            model.browseCapability = nil
                        } label: {
                            Label(capability, systemImage: "xmark.circle.fill").font(.caption.monospaced())
                        }.buttonStyle(.borderless).help("Show every plugin")
                    }
                }
                Spacer()
                if model.loadingRegistry { ProgressView().controlSize(.small) }
                if let fetched = model.registryFetchedAt {
                    Text("Updated \(fetched, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.refreshRegistry(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(model.loadingRegistry).help("Fetch the plugin registry again")
            }
            if let error = model.registryError {
                Label(model.registry == nil ? error : "Showing the saved catalog: \(error)",
                      systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if listings.isEmpty {
                ContentUnavailableView(
                    updatesOnly ? "Everything is up to date" : (model.registry == nil ? "Loading plugins…" : "No plugins found"),
                    systemImage: updatesOnly ? "checkmark.circle" : "puzzlepiece.extension"
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(listings) { listing in PluginListingRow(model: model, listing: listing) }
            }
        }
    }
}

private struct PluginListingRow: View {
    @Bindable var model: PluginManagerModel
    let listing: PluginListing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(listing.entry.name.text).font(.headline)
                    if let version = listing.version { Text("v" + version.version).foregroundStyle(.secondary) }
                    if publisherVerified {
                        Label("BashCut", systemImage: "checkmark.seal.fill").labelStyle(.titleAndIcon)
                            .font(.caption2).foregroundStyle(.cyan)
                    }
                }
                if let summary = listing.entry.summary { Text(summary.text).font(.caption) }
                HStack(spacing: 8) {
                    Text(listing.entry.id).font(.caption2.monospaced())
                    if let category = listing.entry.category { Text(category).font(.caption2) }
                    if let size = listing.version?.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.caption2)
                    }
                    if let extra = listing.version?.downloadBytes, extra > 0 {
                        Text("+ " + ByteCountFormatter.string(fromByteCount: Int64(extra), countStyle: .file) + " setup")
                            .font(.caption2)
                    }
                }.foregroundStyle(.secondary)
                if case .incompatible(let reason) = listing.status {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
                if case .shadowed = listing.status {
                    Text("Installed in this project or the app").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            action
        }.padding(.vertical, 4)
    }

    private var publisherVerified: Bool {
        guard let id = listing.entry.publisher else { return false }
        return model.registry?.publishers[id]?.verified == true
    }

    @ViewBuilder private var action: some View {
        if model.downloading.contains(listing.id) {
            ProgressView().controlSize(.small)
        } else {
            switch listing.status {
            case .available: Button("Install") { install() }.disabled(model.installing)
            case .update(let from):
                Button("Update") { install() }.buttonStyle(.borderedProminent).disabled(model.installing)
                    .help("Installed: v\(from)")
            case .installed, .shadowed: Text("Installed").font(.caption).foregroundStyle(.secondary)
            case .incompatible: EmptyView()
            }
        }
    }

    private func install() {
        Task {
            do { try await model.requestInstall(listing.id) } catch { model.message = error.localizedDescription }
        }
    }
}
