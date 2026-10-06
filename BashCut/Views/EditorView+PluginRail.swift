import BashCutDocument
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

/// The plugin part of the left rail (plugin API 8): one icon per ready plugin with a panel.
extension EditorView {
    func libraryTabSelected(_ tab: LibraryTab) -> Bool {
        document.ui.libraryTab == tab && !pluginPanelShown
    }
    var pluginPanelShown: Bool {
        document.ui.pluginPanel.map { id in document.pluginViews.containers.contains { $0.id == id } } ?? false
    }
    /// Panels of ready plugins with a container (plugin API 8), under the built-in panels.
    @ViewBuilder var pluginRail: some View {
        let containers = document.pluginViews.containers
        if !containers.isEmpty {
            Divider().frame(width: 36).padding(.vertical, 2)
            ForEach(containers, id: \.id) { plugin in
                let selected = document.ui.pluginPanel == plugin.id
                Button {
                    document.showPluginPanel(plugin.id)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: plugin.manifest.container?.icon ?? "puzzlepiece.extension").font(.system(size: 16))
                        Text(verbatim: plugin.manifest.containerTitle).font(.system(size: 8)).lineLimit(1)
                    }
                    .frame(width: 48, height: 42)
                    .background(selected ? Color.cyan.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(selected ? .cyan : .secondary)
                    .help(plugin.manifest.displayName)
            }
        }
    }
}
