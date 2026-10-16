import AppKit
import BashCutDocument
import BashCutPlugin
import SwiftUI

private final class PluginWindowDelegate: NSObject, NSWindowDelegate {
    let closed: () -> Void
    init(closed: @escaping () -> Void) { self.closed = closed }
    func windowWillClose(_ notification: Notification) { closed() }
}

/// Plugin views that live in a window of their own (plugin API 11 `location: window`, D2): a plain non-modal
/// `NSWindow` like the detached agent dock, so the editor stays usable behind it. Closing the window only hides it:
/// the view keeps its tree, values and scroll position until the project closes or switches (`closeAll`). Dock shows
/// the same view over the viewer instead; Undock brings the window back.
@MainActor final class PluginViewWindows {
    unowned let document: ProjectDocument
    private var windows: [String: NSWindow] = [:]
    private var delegates: [String: PluginWindowDelegate] = [:]

    init(document: ProjectDocument) { self.document = document }

    /// Opens (or brings forward) the window of `key`; a docked view stays where it is.
    func open(_ key: String) {
        guard document.ui.dockedPluginView != key, let model = document.pluginViews.model(key: key) else { return }
        let window = windows[key] ?? makeWindow(key, model: model)
        document.ui.pluginWindows.insert(key)
        model.visible = true
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window of `key` (or its docked view). The view keeps its state for the next time it opens.
    func close(_ key: String) {
        if document.ui.dockedPluginView == key {
            document.ui.dockedPluginView = nil
            hidden(key)
        }
        windows[key]?.close()
    }

    /// Shows the view over the viewer instead of in its window.
    func dock(_ key: String) {
        guard document.pluginViews.resolve(key) != nil else { return }
        if let docked = document.ui.dockedPluginView, docked != key { hidden(docked) }
        // `orderOut` hides the window without the close callback, so the view stays visible for the docked host.
        windows[key]?.orderOut(nil)
        document.ui.pluginWindows.remove(key)
        document.ui.dockedPluginView = key
        document.pluginViews.model(key: key)?.visible = true
    }

    /// Puts the docked view back in its window.
    func undock() {
        guard let key = document.ui.dockedPluginView else { return }
        document.ui.dockedPluginView = nil
        open(key)
    }

    /// Closes and releases every window (project closed or switched); their views are forgotten by `reset`.
    func closeAll() {
        document.ui.dockedPluginView = nil
        for (key, window) in windows {
            window.delegate = nil
            window.close()
            hidden(key)
        }
        windows = [:]
        delegates = [:]
        document.ui.pluginWindows = []
    }

    private func hidden(_ key: String) {
        document.ui.pluginWindows.remove(key)
        // The model may already be gone after a reset; it renders again from its state when it shows next time.
        document.pluginViews.existingModel(key: key)?.visible = false
    }

    private func makeWindow(_ key: String, model: PluginViewModel) -> NSWindow {
        // The editor even when the app is in the background (a window opened by a command line).
        let editor = NSApp.windows.first { $0.contentView is NSHostingView<EditorView> } ?? NSApp.mainWindow
        let size = PluginWindowLayout.defaultSize(editor: editor?.frame.size)
        let window = AuxiliaryWindow.make(
            title: document.pluginViews.resolve(key)?.1.title.text ?? key, size: size,
            minSize: PluginWindowLayout.minimum,
            content: PluginWindowView(document: document, key: key, model: model, docked: false))
        let delegate = PluginWindowDelegate { [weak self] in self?.hidden(key) }
        delegates[key] = delegate
        window.delegate = delegate
        // Size and position are remembered per view; the first time it opens centred over the editor.
        let autosave = "BashCut.PluginWindow." + key
        if !window.setFrameUsingName(autosave) {
            if let frame = editor?.frame {
                window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            } else {
                window.center()
            }
        }
        window.setFrameAutosaveName(autosave)
        windows[key] = window
        return window
    }
}

/// A window view (`location: window`) in its window or docked over the viewer: a header with the title, Dock or
/// Undock and Close (Esc), then the view.
struct PluginWindowView: View {
    @Bindable var document: ProjectDocument
    let key: String
    @Bindable var model: PluginViewModel
    let docked: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let (plugin, view) = document.pluginViews.resolve(key) {
                    Image(systemName: view.icon ?? plugin.manifest.container?.icon ?? "puzzlepiece.extension")
                        .foregroundStyle(.cyan)
                    Text(verbatim: view.title.text).font(.headline)
                }
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                if docked {
                    Button { document.pluginViews.windows.undock() } label: {
                        Label("Undock", systemImage: "macwindow")
                    }.help("Show this view in its own window again")
                } else {
                    Button { document.pluginViews.windows.dock(key) } label: {
                        Label("Dock", systemImage: "rectangle.inset.filled")
                    }.help("Show this view over the viewer")
                }
                Button("Close") { document.pluginViews.windows.close(key) }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            PluginViewColumn(model: model, tracksVisibility: false)
        }
    }
}

/// The docked window view over the viewer area (D2), while `ui.dockedPluginView` names one.
struct PluginDockedViewHost: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        if let key = document.ui.dockedPluginView, let model = document.pluginViews.model(key: key) {
            PluginWindowView(document: document, key: key, model: model, docked: true)
                .background(Color.editorBackground)
        }
    }
}
