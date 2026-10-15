import BashCutDocument
import BashCutPlugin
import SwiftUI

/// Presents plugin views that live in a sheet (plugin API 8 `location: sheet`).
struct PluginSheetPresenter: ViewModifier {
    @Bindable var document: ProjectDocument

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { document.ui.pluginSheet != nil }, set: { if !$0 { document.ui.pluginSheet = nil } }
        )) {
            if let key = document.ui.pluginSheet { PluginSheetView(document: document, key: key) }
        }
    }
}

/// The plugin part of the left rail (plugin API 8): the panels of ready plugins with a container are listed in the
/// More popover at the end of the rail, and one opens in the library column. A plugin's tool views are in Tools.
extension EditorView {
    func libraryTabSelected(_ tab: LibraryTab) -> Bool {
        document.ui.libraryTab == tab && !pluginPanelShown
    }
    var pluginPanelShown: Bool {
        document.ui.pluginPanel.map { id in document.pluginViews.containers.contains { $0.id == id } } ?? false
    }

    /// The More tile: shown when a ready plugin has a panel, selected while one of them is open.
    @ViewBuilder func railMore(compact: Bool) -> some View {
        let containers = document.pluginViews.containers
        if !containers.isEmpty {
            let selected = pluginPanelShown
            Button {
                showRailMore.toggle()
            } label: {
                railTile(icon: "ellipsis", label: "More", selected: selected, compact: compact)
            }
            .buttonStyle(.plain).foregroundStyle(selected ? .cyan : .secondary)
            .help("More: plugin panels")
            .popover(isPresented: $showRailMore, arrowEdge: .trailing) { railMoreList(containers) }
        }
    }

    private func railMoreList(_ containers: [InstalledPlugin]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Plugin panels").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            ForEach(containers, id: \.id) { plugin in
                let selected = document.ui.pluginPanel == plugin.id
                Button {
                    showRailMore = false
                    if selected, document.ui.showLibraryPanel {
                        document.run(.toggleLibraryPanel)
                    } else {
                        document.showPluginPanel(plugin.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: plugin.manifest.container?.icon ?? "puzzlepiece.extension").frame(width: 20)
                        Text(verbatim: plugin.manifest.containerTitle)
                        Spacer(minLength: 12)
                        if selected { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(plugin.manifest.displayName)
            }
        }.padding(6).frame(minWidth: 180)
    }
}
