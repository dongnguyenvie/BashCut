import AppKit
import BashCutAutomation
import BashCutDocument
import SwiftUI

/// The window toolbar, drawn in the title bar: the project, undo/redo and format on the left, what the app is
/// doing in the middle, and the daily actions on the right. Rare project-level commands live in ☰ and in the
/// menu bar (`MainMenu`), which has every command.
extension EditorView {
    var toolbar: some View {
        HStack(spacing: 8) {
            projectMenu
            Divider().frame(height: 18)
            Button { document.run(.undo) } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo (⌘Z)").action(.undo, in: document)
            Button { document.run(.redo) } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo (⇧⌘Z)").action(.redo, in: document)
            formatMenu
            Spacer(minLength: 8)
            // A narrow window folds the plugin actions, Plugins and Review into ☰ and the activity into an icon,
            // instead of pushing the row under the window buttons (#528).
            ViewThatFits(in: .horizontal) {
                trailingItems(compact: false)
                trailingItems(compact: true)
            }
            PluginShortcutButtons(document: document)
        }
        .controlSize(.small)
        // Room for the window's close, minimize and zoom buttons, which sit on this row.
        .padding(.leading, 80).padding(.trailing, 10)
        .frame(height: EditorView.toolbarHeight)
        .background(WindowDragArea())
        .disabled(document.busy)
    }

    static let toolbarHeight = 38.0

    private func trailingItems(compact: Bool) -> some View {
        HStack(spacing: 8) {
            // Nothing sits here while the agent is idle and nothing runs: the save state is the dot on the project
            // name, export progress is on the Export button and the plugin edits dot is on Plugins.
            if document.activity.status != .idle { AgentStatusButton(document: document, compact: compact) }
            if document.busy { ProgressView().controlSize(.mini).help("Working…") }
            Spacer(minLength: 8)
            if !compact {
                PluginActionStrip(document: document, placement: "toolbar", compact: true)
                pluginsButton
                Button("Review") { document.run(.showReview) }.help("Review before export (⇧⌘R)")
                    .action(.showReview, in: document)
                Divider().frame(height: 18)
            }
            exportButton
            moreMenu(compact: compact)
            // Inspector and agent are separate columns, each with its own toggle.
            Button { document.run(.toggleInspector) } label: { Image(systemName: "slider.horizontal.3") }
                .help("Show or hide the Inspector (⌃⌘I)").accessibilityLabel("Inspector")
                .foregroundStyle(document.ui.inspectorShown ? Color.cyan : Color.primary)
                .action(.toggleInspector, in: document)
            Button { document.run(.toggleAgentDock) } label: { Image(systemName: "sidebar.right") }
                .help("Show or hide the agent dock (⌘J)").accessibilityLabel("Agent dock")
                .foregroundStyle(document.ui.showAgentDock && !document.agents.isDetached ? Color.cyan : Color.primary)
                .action(.toggleAgentDock, in: document)
        }
    }

    private var projectName: String {
        document.fileURL == nil ? String(localized: "No project") : document.project.name
    }

    /// The project name; its menu reveals the project and switches to another one.
    private var projectMenu: some View {
        Menu {
            if let url = document.fileURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Divider()
            }
            recentProjects
            Button("Open Project…") { document.run(.openProject) }
            Button("New Project…") { document.run(.newProject) }
            if document.fileURL != nil {
                Divider()
                Button("Close Project") { document.run(.closeProject) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(projectName).fontWeight(.semibold).lineLimit(1).frame(maxWidth: 200)
                if document.fileURL != nil {
                    // Grey while there are unsaved changes (BashCut saves every 30 seconds), green when saved.
                    Circle().fill(document.dirty ? Color.secondary : Color.green).frame(width: 6, height: 6)
                        .help(String(
                            format: String(localized: "%@ · rev %d"),
                            document.dirty ? String(localized: "Edited") : String(localized: "Saved"),
                            document.project.revision))
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Project: reveal in Finder, open another, close it")
    }

    @ViewBuilder private var recentProjects: some View {
        let recents = Array(document.settings.recentHistory.prefix(SettingsModel.recentProjectLimit))
        if !recents.isEmpty {
            Menu("Open Recent") {
                ForEach(Array(zip(recents, RecentProject.menuTitles(recents))), id: \.0.url) { project, title in
                    Button(title) { document.openProject(at: project.url) }.help(project.folder.path)
                }
                Divider()
                Button("View All…") { document.run(.showRecentProjects) }
                Button("Clear Menu") { document.run(.clearRecentProjects) }
            }
        }
    }

    /// Plugins sit beside Review and Export so they are found; the dot means updates (cyan) or edits to review
    /// (orange), and the click opens what needs attention.
    private var pluginsButton: some View {
        let updates = document.plugins.updates.count
        let proposals = document.plugins.proposals.count
        return Button {
            if proposals > 0 {
                document.ui.showPluginProposals = true
            } else {
                if updates > 0 { document.plugins.tab = .updates }
                document.run(.showPlugins)
            }
        } label: {
            Label(
                updates > 0 ? String(format: String(localized: "Plugins (%d)"), updates) : String(localized: "Plugins"),
                systemImage: "puzzlepiece.extension")
        }
        .action(.showPlugins, in: document)
        .overlay(alignment: .topTrailing) {
            if updates > 0 || proposals > 0 {
                Circle().fill(proposals > 0 ? Color.orange : Color.cyan).frame(width: 7, height: 7).offset(x: 3, y: -3)
            }
        }
        .help(proposals > 0 ? String(format: String(localized: "Review Plugin Edits (%d)"), proposals)
            : updates > 0 ? String(localized: "Plugin updates are available") : String(localized: "Plugins: install, update and manage"))
    }

    /// Export…, or the running export's progress; then a click shows its details and Cancel. ⌘E always opens
    /// the Export sheet, so another export can be queued.
    private var exportButton: some View {
        let exports = document.exports
        return Button {
            document.run(exports.isRunning ? .showExportProgress : .showExport)
        } label: {
            if exports.isRunning {
                HStack(spacing: 5) {
                    ExportProgressRing(progress: exports.progress)
                    Text(exports.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
            } else {
                Text("Export…")
            }
        }
        .help(exports.isRunning ? String(localized: "Export progress: details and cancel") : String(localized: "Export (⌘E)"))
        .accessibilityLabel(exports.isRunning ? String(localized: "Export progress") : String(localized: "Export…"))
        .shortcut(.showExport)
        .disabled(!document.canPerform(exports.isRunning ? .showExportProgress : .showExport))
        .buttonStyle(ExportButtonStyle())
        .popover(isPresented: Bindable(document.ui).showExportProgress, arrowEdge: .bottom) {
            ExportProgressPopover(document: document)
        }
    }

    /// ☰: project, history and app commands that do not need a toolbar button of their own; in a narrow window
    /// also the toolbar's plugin actions, Plugins and Review.
    private func moreMenu(compact: Bool) -> some View {
        let plugins = document.plugins.updates.count + document.plugins.proposals.count
        return Menu {
            if compact {
                Section {
                    PluginActionStrip(document: document, placement: "toolbar", compact: true)
                    Button(plugins > 0 ? String(format: String(localized: "Plugins (%d)…"), plugins) : String(localized: "Plugins…")) {
                        if document.plugins.proposals.isEmpty { document.run(.showPlugins) } else { document.ui.showPluginProposals = true }
                    }
                    Button("Review…") { document.run(.showReview) }.disabled(!document.canPerform(.showReview))
                }
            }
            Section {
                Button("New Project…") { document.run(.newProject) }
                Button("Open Project…") { document.run(.openProject) }
                recentProjects
                Button("Save") { document.run(.saveProject) }.disabled(!document.canPerform(.saveProject))
                Button("Import Footage…") { document.run(.importMedia) }.disabled(!document.canPerform(.importMedia))
            }
            Button("History…") { document.run(.showHistory) }
            if document.exports.report != nil { Button("Export report") { document.ui.showExportReport = true } }
            Section {
                Button("Agent Skills…") { document.run(.showAgentKit) }
                Button("Doctor…") { document.run(.showDoctor) }
                Button("Settings…") { document.run(.showSettings) }
            }
            Section {
                Button(document.ui.showLibraryPanel ? "Hide Library Panel" : "Show Library Panel") {
                    document.run(.toggleLibraryPanel)
                }
                Button(document.ui.inspectorShown ? "Hide Inspector" : "Show Inspector") { document.run(.toggleInspector) }
            }
            Section {
                Button("Command Palette…") { document.run(.showCommands) }
                Button("Keyboard Shortcuts…") { document.run(.showShortcuts) }
            }
            Section {
                if let issues = AppLinks.current.issues {
                    Button("Report an Issue…") { NSWorkspace.shared.open(issues) }
                }
                if document.showsAppUpdateNotice, let release = document.appUpdate.available {
                    Button(String(format: String(localized: "Update to BashCut %@…"), release.version)) {
                        document.run(.showUpdates)
                    }
                } else {
                    Button("Check for Updates…") { document.run(.showUpdates) }
                }
                Button("About BashCut") { document.run(.showAbout) }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .overlay(alignment: .topTrailing) {
            // A newer BashCut is out; ☰ › Update to … opens Software Update.
            if document.showsAppUpdateNotice || (compact && plugins > 0) {
                Circle().fill(Color.cyan).frame(width: 7, height: 7).offset(x: 3, y: -3).allowsHitTesting(false)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("More")
        .help("More")
    }
}

/// Empty toolbar space that moves the window like a title bar, and zooms or minimizes it on a double-click
/// as System Settings › Desktop & Dock says.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// The toolbar's one filled button: cyan with dark text. The system prominent style turns grey when the window is
/// not key, which made Export look disabled; this keeps the cyan, a little softer.
private struct ExportButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let inactive = activeState == .inactive
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.cyan))
            .opacity(!isEnabled ? 0.4 : inactive ? 0.7 : configuration.isPressed ? 0.8 : 1)
    }
}
