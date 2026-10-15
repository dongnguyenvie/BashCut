import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// A plugin view on its own (a dock tab, a sheet or a window): a lazy scrolling column, visible while it is on screen.
/// A window sets `tracksVisibility` false: it says itself when the view shows, since a closed window keeps its views.
struct PluginViewColumn: View {
    @Bindable var model: PluginViewModel
    var tracksVisibility = true

    var body: some View {
        Group {
            if let split = model.tree?.fillingSplit {
                // A view that is one split fills the host, and each column scrolls on its own (API 11).
                VStack(alignment: .leading, spacing: 0) {
                    if model.tree?.title != nil || model.error != nil {
                        VStack(alignment: .leading, spacing: 8) { PluginViewRows(model: model, showsBody: false) }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        Divider()
                    }
                    PluginSplitView(node: split, model: model, fills: true)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        PluginViewRows(model: model)
                    }.padding(12)
                }
            }
        }
        .task(id: model.pluginID + "/" + model.viewID) {
            guard tracksVisibility else { return }
            model.visible = true
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            model.visible = false
        }
    }
}

/// The sheet for plugin views that live in one (`location: sheet`): the view and a Close button.
struct PluginSheetView: View {
    @Bindable var document: ProjectDocument
    let key: String

    var body: some View {
        VStack(spacing: 0) {
            if let (plugin, view) = document.pluginViews.resolve(key),
                let model = document.pluginViews.model(key: key) {
                HStack(spacing: 6) {
                    Image(systemName: view.icon ?? plugin.manifest.container?.icon ?? "puzzlepiece.extension")
                        .foregroundStyle(.cyan)
                    Text(verbatim: view.title.text).font(.headline)
                    // The plugin name only when it says more than the title ("Online resources" by "Online Resources").
                    if plugin.manifest.displayName.caseInsensitiveCompare(view.title.text) != .orderedSame {
                        Text(verbatim: plugin.manifest.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close") { document.ui.pluginSheet = nil }.keyboardShortcut(.cancelAction)
                }.padding(12)
                Divider()
                // A sheet starts fresh each time it opens (a form, not a place to come back to).
                PluginViewColumn(model: model).onDisappear { model.forget() }
            } else {
                Text("This plugin view is no longer available").padding()
                Button("Close") { document.ui.pluginSheet = nil }.padding(.bottom)
            }
        }
        // Big enough for a results grid of 3 × 4 tiles; the grid adds columns as the sheet grows.
        .frame(minWidth: 900, idealWidth: 1100, maxWidth: .infinity, minHeight: 600, idealHeight: 720, maxHeight: .infinity)
    }
}

/// A plugin view as rows of the panel's lazy column: its title, an error, then its top-level components.
struct PluginViewRows: View {
    @Bindable var model: PluginViewModel
    /// False for the header of a view whose split the host draws itself.
    var showsBody = true

    var body: some View {
        if let title = model.tree?.title {
            HStack {
                Text(verbatim: title).font(.subheadline.bold())
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
        } else if model.busy {
            ProgressView().controlSize(.small)
        }
        if let error = model.error {
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .textSelection(.enabled)
                Button("Try Again") { model.load() }.controlSize(.small)
            }
        }
        if showsBody, let tree = model.tree {
            ForEach(tree.body) { node in PluginNodeView(node: node, model: model) }
        }
    }
}

/// Plugin views that live in the Inspector (`location: inspector`), under the selected item's controls. Each renders
/// again from scratch when the selection or the selected item's media changes (debounced; a render for an older
/// selection is cancelled); a view whose `when` does not match is not asked, and one that answers an empty body
/// takes no room.
struct PluginInspectorViews: View {
    @Bindable var document: ProjectDocument
    let item: Item

    var body: some View {
        let views = document.pluginViews.inspectorViews
        let facts = views.contains { $0.view.when != nil } ? document.pluginFacts() : [:]
        ForEach(views, id: \.key) { entry in
            PluginInspectorSection(
                model: document.pluginViews.model(plugin: entry.plugin.id, view: entry.view.id),
                selection: item.id + "|" + (item.mediaID ?? ""),
                matches: entry.view.condition?.evaluate(facts) ?? true)
        }
    }
}

private struct PluginInspectorSection: View {
    @Bindable var model: PluginViewModel
    let selection: String
    let matches: Bool

    private var shows: Bool { matches && (model.error != nil || !(model.tree?.body.isEmpty ?? true)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shows {
                Divider()
                PluginViewRows(model: model)
            }
        }
        .task(id: selection + (matches ? "" : "|off")) { model.followSelection(matches: matches) }
        .onDisappear { model.stopFollowing() }
    }
}
