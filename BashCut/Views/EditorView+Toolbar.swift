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
            activity
            Spacer(minLength: 8)
            PluginActionStrip(document: document, placement: "toolbar", compact: true)
            PluginShortcutButtons(document: document)
            pluginsButton
            Button("Review") { document.run(.showReview) }.help("Review before export (⇧⌘R)")
                .action(.showReview, in: document)
            Divider().frame(height: 18)
            Button("Export…") { document.run(.showExport) }.help("Export (⌘E)")
                .action(.showExport, in: document).buttonStyle(.borderedProminent)
            moreMenu
            Button { document.run(.toggleAgentDock) } label: { Image(systemName: "sidebar.right") }
                .help("Show or hide the agent dock (⌘J)").accessibilityLabel("Agent dock")
                .action(.toggleAgentDock, in: document)
        }
        .controlSize(.small)
        // Room for the window's close, minimize and zoom buttons, which sit on this row.
        .padding(.leading, 80).padding(.trailing, 10)
        .frame(height: EditorView.toolbarHeight)
        .background(WindowDragArea())
        .disabled(document.busy)
    }

    static let toolbarHeight = 38.0

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
        } label: {
            HStack(spacing: 5) {
                Text(projectName).fontWeight(.semibold).lineLimit(1).frame(maxWidth: 200)
                if document.dirty {
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                        .help("Unsaved changes; BashCut saves automatically every 30 seconds")
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Project: reveal in Finder, open another")
    }

    @ViewBuilder private var recentProjects: some View {
        let recents = document.settings.recentProjects
        if !recents.isEmpty {
            Menu("Open Recent") {
                ForEach(recents, id: \.path) { url in
                    Button(url.deletingLastPathComponent().lastPathComponent) { document.openProject(at: url) }
                }
                Divider()
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

    /// ☰: project, history and app commands that do not need a toolbar button of their own.
    private var moreMenu: some View {
        Menu {
            Section {
                Button("New Project…") { document.run(.newProject) }
                Button("Open Project…") { document.run(.openProject) }
                recentProjects
                Button("Save") { document.run(.saveProject) }.disabled(!document.canPerform(.saveProject))
                Button("Import Footage…") { document.run(.importMedia) }.disabled(!document.canPerform(.importMedia))
            }
            Button("History…") { document.run(.showHistory) }
            Section {
                Button("Agent Skills…") { document.run(.showAgentKit) }
                Button("Doctor…") { document.run(.showDoctor) }
                Button("Settings…") { document.run(.showSettings) }
            }
            Section {
                Button("Command Palette…") { document.run(.showCommands) }
                Button("Keyboard Shortcuts…") { document.run(.showShortcuts) }
            }
            Section {
                if let issues = AppLinks.current.issues {
                    Button("Report an Issue…") { NSWorkspace.shared.open(issues) }
                }
                Button("About BashCut") { MainMenu.showAbout() }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("More")
        .help("More")
    }

    /// What the app is doing: export progress, work in progress, plugin edits waiting, or the save state.
    private var activity: some View {
        HStack(spacing: 6) {
            if document.exports.isRunning {
                ProgressView(value: document.exports.progress).frame(width: 80)
                Text(document.exports.queue.detail ?? String(localized: "Exporting")).lineLimit(1)
                Text(document.exports.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                if document.exports.queue.queuedCount > 0 {
                    Text("\(document.exports.queue.queuedCount) queued").foregroundStyle(.secondary)
                }
                Button(action: document.exports.cancelActive) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel export")
            } else if document.busy {
                ProgressView().controlSize(.mini)
                Text("Working…")
            } else if !document.plugins.proposals.isEmpty {
                Button {
                    document.ui.showPluginProposals = true
                } label: {
                    Label("\(document.plugins.proposals.count) plugin edits", systemImage: "puzzlepiece.extension.fill")
                }.buttonStyle(.plain).foregroundStyle(.orange).help("Review edits plugin hooks proposed")
            } else if document.fileURL != nil {
                Image(systemName: document.dirty ? "circle.fill" : "checkmark.circle")
                    .foregroundStyle(document.dirty ? Color.secondary : Color.green).imageScale(.small)
                Text(document.dirty ? "Edited" : "Saved")
                Text(String(format: "rev %d", document.project.revision)).foregroundStyle(.secondary).monospacedDigit()
                if document.exports.report != nil {
                    Button("Export report") { document.ui.showExportReport = true }.buttonStyle(.link)
                }
            } else {
                Text("BashCut").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).frame(minWidth: 220).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08)))
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
