import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// The library panel left of the viewer (P1-10): as wide as the user dragged it, or, in wide mode, 760 pt over the
/// viewer with a category sidebar.
extension EditorView {
    @ViewBuilder var libraryPane: some View {
        let width = EditorLayout.libraryWidth(document.ui)
        if document.ui.libraryWide, pluginPanelContainer == nil {
            // The panel keeps its place in the row and draws wider than it, over the viewer.
            Color.clear.frame(width: width)
                .overlay(alignment: .leading) {
                    libraryContent.frame(width: LibraryPanelMetrics.wideWidth)
                        .background(Color.editorBackground)
                        .overlay(alignment: .trailing) { Divider() }
                        .shadow(color: .black.opacity(0.4), radius: 12, x: 4)
                }
        } else {
            // Each pane is clipped to its frame: a child wider than its pane would draw over its neighbours (#484).
            // It may be narrower than asked in a small window, so the viewer keeps its minimum.
            libraryContent
                .frame(minWidth: LibraryPanelMetrics.widthRange.lowerBound, idealWidth: width, maxWidth: width).clipped()
        }
    }

    private var pluginPanelContainer: InstalledPlugin? {
        document.ui.pluginPanel.flatMap { id in document.pluginViews.containers.first { $0.id == id } }
    }

    private var libraryContent: some View {
        Group {
            if let plugin = pluginPanelContainer {
                PluginPanelView(document: document, plugin: plugin)
            } else {
                LibraryView(document: document, pluginManager: document.plugins)
            }
        }
    }
}
