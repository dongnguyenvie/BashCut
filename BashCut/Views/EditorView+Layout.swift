import AppKit
import BashCutDocument
import SwiftUI

/// The editor's pane sizes and the smallest window they fit in (#528). The window cannot become smaller than
/// `minSize`, so its content is never centred over the title bar; the library panel, the Inspector and the agent
/// dock can be hidden to give a small window room.
enum EditorLayout {
    static let railWidth = 54.0
    static let libraryWidth = 225.0
    static let inspectorWidth = 220.0
    static let viewerMinWidth = 260.0
    /// The editor column (panes, timeline toolbar and timeline): the timeline toolbar needs this much.
    static let editorMinWidth = 860.0
    static let dockMinWidth = 330.0
    static let paneMinHeight = 220.0
    /// The timeline is resizable against the panes above it, from `timelineMinHeight` up.
    static let timelineMinHeight = 170.0
    static let timelineIdealHeight = 330.0
    static let minHeight = 600.0

    /// The smallest content size: the editor column, plus the agent dock while it is shown in the window.
    static func minSize(dock: Bool) -> CGSize {
        CGSize(width: editorMinWidth + (dock ? dockMinWidth + 1 : 0), height: minHeight)
    }
}

extension EditorView {
    /// The run panel and the agent change and export toasts: bottom right of the panes, just above the timeline.
    /// They belong to the editor column, so they never sit over the agent dock beside it.
    var toastStack: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if document.fileURL != nil, document.runPanel.visible {
                RunPanelView(document: document, model: document.runPanel)
            }
            if let notice = document.exports.notice {
                ExportToast(notice: notice, document: document)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let change = document.agentChange {
                AgentChangeToast(
                    change: change, canUndo: document.canUndoAgentChange,
                    show: { document.run(.showAgentChanges) },
                    undo: { document.run(.undoAgentChange) },
                    dismiss: { document.run(.dismissAgentChange) })
            }
        }
        .animation(.easeOut(duration: 0.2), value: document.exports.notice?.id)
    }

    /// The panes over the timeline; the timeline is resizable against them.
    var editorColumn: some View {
        VSplitView {
            HStack(spacing: 0) {
                // Each pane is clipped to its frame: a child wider than its pane is centred and
                // would otherwise draw over the neighbouring panes (#484).
                // The rail scrolls when a short window cannot fit every panel and plugin panel.
                ScrollView(.vertical, showsIndicators: false) { rail }.frame(width: EditorLayout.railWidth).clipped()
                Divider()
                if document.ui.showLibraryPanel {
                    Group {
                        if let id = document.ui.pluginPanel,
                            let plugin = document.pluginViews.containers.first(where: { $0.id == id }) {
                            PluginPanelView(document: document, plugin: plugin)
                        } else {
                            LibraryView(document: document, pluginManager: document.plugins)
                        }
                    }.frame(width: EditorLayout.libraryWidth).clipped()
                    Divider()
                }
                Group {
                    if document.sourceViewer.visible {
                        SourceViewer(document: document, source: document.sourceViewer)
                    } else {
                        viewer
                    }
                }.frame(minWidth: EditorLayout.viewerMinWidth, maxWidth: .infinity).clipped()
                if document.ui.showInspector {
                    Divider()
                    InspectorView(document: document).frame(width: EditorLayout.inspectorWidth).clipped()
                }
            }.frame(minHeight: EditorLayout.paneMinHeight).disabled(document.busy)
                .overlay(alignment: .bottomTrailing) { toastStack }
            // The timeline is resizable against the panes above it (#528).
            VStack(spacing: 0) {
                timelineToolbar
                TimelineView(document: document)
                    .help("Option-drag an edge to roll; Command-drag a clip to slip; Shift-Delete to lift.")
                    .disabled(document.busy)
            }.frame(minHeight: EditorLayout.timelineMinHeight, idealHeight: EditorLayout.timelineIdealHeight)
        }.frame(minWidth: EditorLayout.editorMinWidth)
    }
}

/// Keeps the window's `contentMinSize` at `size`, and grows a smaller window to it (opening the agent dock in a
/// small window), within the screen.
struct WindowMinSize: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Probe)?.size = size
    }

    private final class Probe: NSView {
        var size: CGSize = .zero { didSet { if size != oldValue { apply() } } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, size != .zero else { return }
            window.contentMinSize = size
            let content = window.contentRect(forFrameRect: window.frame).size
            guard content.width < size.width || content.height < size.height, !window.styleMask.contains(.fullScreen)
            else { return }
            var frame = window.frameRect(forContentRect: NSRect(
                origin: .zero, size: CGSize(width: max(content.width, size.width), height: max(content.height, size.height))))
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
                frame.origin.y = max(min(frame.minY, visible.maxY - frame.height), visible.minY)
            }
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
