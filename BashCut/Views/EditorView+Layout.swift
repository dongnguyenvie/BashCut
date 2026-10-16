import AppKit
import BashCutDocument
import BashCutProject
import SwiftUI

/// The editor's pane sizes and the smallest window they fit in (#528). The window cannot become smaller than
/// `minSize`, so its content is never centred over the title bar; the library panel, the Inspector and the agent
/// dock can be hidden to give a small window room.
enum EditorLayout {
    static let railWidth = 54.0
    /// A window shorter than this shows the rail's tiles without labels (the label becomes the tooltip), so the rail
    /// never overflows (P1-3).
    static let railLabelsMinHeight = 900.0
    /// The Inspector and agent columns: wide at 1680 pt or more, narrower below.
    static let rightColumnWideWidth = 340.0
    static let rightColumnWidth = 300.0
    static let rightColumnWideFrom = 1680.0
    /// The library panel: dragged between 300 and 520 pt; without a choice 372 on a screen of 1680 pt or more, else 300
    /// (P1-10). It gives way to the viewer in a small window.
    @MainActor static func libraryWidth(_ ui: EditorUIState) -> Double {
        ui.libraryWidth ?? LibraryPanelMetrics.defaultWidth(screenWidth: Double(NSScreen.main?.frame.width ?? 1440))
    }
    static let viewerMinWidth = 260.0
    /// The editor column (panes, timeline toolbar and timeline): the timeline toolbar needs this much.
    static let editorMinWidth = 860.0
    static let paneMinHeight = 220.0
    /// The timeline is resizable against the panes above it, from `timelineMinHeight` up.
    static let timelineMinHeight = 170.0
    static let timelineIdealHeight = 330.0
    static let minHeight = 600.0

    /// The smallest content size: the editor column, plus the agent column beside it. The Inspector sits beside the
    /// viewer, inside the editor column.
    static func minSize(agentColumn: Bool) -> CGSize {
        CGSize(width: editorMinWidth + (agentColumn ? rightColumnWidth + 1 : 0), height: minHeight)
    }

    static let sidePaneBackground = Color(red: 0.045, green: 0.05, blue: 0.06)

    static func rightColumnWidth(window: Double) -> Double {
        window >= rightColumnWideFrom ? rightColumnWideWidth : rightColumnWidth
    }
}

extension EditorView {
    var inspectorPane: some View {
        InspectorView(document: document, formatMenu: AnyView(formatMenu), platformMenu: AnyView(platformMenu))
            .frame(width: columnWidth).clipped().background(EditorLayout.sidePaneBackground)
    }
    var agentPane: some View {
        AgentDockView(model: document.agents).frame(width: columnWidth).clipped().background(EditorLayout.sidePaneBackground)
    }
    var columnWidth: Double { EditorLayout.rightColumnWidth(window: windowWidth) }
    /// The Inspector sits beside the viewer and the timeline spans the editor's width under it (design 7b).
    var inspectorColumn: Bool { document.ui.inspectorShown }
    /// The agent column runs the full height at the window's right edge, beside the timeline too (a terminal needs
    /// the height). It is independent of the Inspector, so selecting a timeline item never takes it away.
    var agentColumn: Bool { document.ui.showAgentDock && !document.agents.isDetached }

    /// The run panel and the agent change and export toasts: bottom right of the timeline, over its lowest tracks
    /// and clear of the scroll bar. They belong to the editor column, so they never sit over the agent dock beside it,
    /// nor over the viewer's transport and timecode. The stack stays inside the timeline's height: the toasts keep
    /// their size and the run panel takes what is left, scrolling its stages when the timeline is short.
    var toastStack: some View {
        GeometryReader { area in
            VStack(alignment: .trailing, spacing: 0) {
                if document.fileURL != nil, document.runPanel.visible {
                    RunPanelView(document: document, model: document.runPanel)
                }
                Group {
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
                }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }
            .frame(maxHeight: area.size.height, alignment: .bottom)
            .frame(width: area.size.width, height: area.size.height, alignment: .bottomTrailing)
        }
        .animation(.easeOut(duration: 0.2), value: document.exports.notice?.id)
    }

    /// The panes over the timeline; the timeline is resizable against them.
    var editorColumn: some View {
        VSplitView {
            HStack(spacing: 0) {
                // Each pane is clipped to its frame: a child wider than its pane is centred and
                // would otherwise draw over the neighbouring panes (#484).
                // The rail drops its labels in a short window; it still scrolls if even the icons do not fit.
                ScrollView(.vertical, showsIndicators: false) { rail }.frame(width: EditorLayout.railWidth).clipped()
                Divider()
                if document.ui.showLibraryPanel {
                    libraryPane.zIndex(1)
                    if document.ui.libraryWide { Divider() } else { LibraryResizeHandle(document: document) }
                }
                Group {
                    if document.sourceViewer.visible {
                        SourceViewer(document: document, source: document.sourceViewer)
                    } else {
                        viewer
                    }
                }
                // A plugin window view docked over the viewer (D2); Undock or Esc leaves it.
                .overlay { PluginDockedViewHost(document: document) }
                .frame(minWidth: EditorLayout.viewerMinWidth, maxWidth: .infinity).clipped()
                if inspectorColumn {
                    Divider()
                    inspectorPane
                }
            }.frame(minHeight: EditorLayout.paneMinHeight).disabled(document.busy)
            // The timeline is resizable against the panes above it (#528).
            VStack(spacing: 0) {
                timelineToolbar
                TimelineView(document: document)
                    .help("Option-drag an edge to roll; Command-drag a clip to slip; Shift-Delete to lift.")
                    .disabled(document.busy)
                    .overlay(alignment: .bottomTrailing) { toastStack.padding(.bottom, 14) }
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
