import BashCutDocument
import BashCutPlugin
import SwiftUI

/// A plugin view on its own (a dock tab or a sheet): a lazy scrolling column, visible while it is on screen.
struct PluginViewColumn: View {
    @Bindable var model: PluginViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                PluginViewRows(model: model)
            }.padding(12)
        }
        .task(id: model.pluginID + "/" + model.viewID) {
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
                    Text(verbatim: plugin.manifest.displayName).font(.caption).foregroundStyle(.secondary)
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
        .frame(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 520)
    }
}

/// A plugin view as rows of the panel's lazy column: its title, an error, then its top-level components.
struct PluginViewRows: View {
    @Bindable var model: PluginViewModel

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
        if let tree = model.tree {
            ForEach(tree.body) { node in PluginNodeView(node: node, model: model) }
        }
    }
}
