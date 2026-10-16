import AppKit
import SwiftUI

extension Color {
    /// The editor's background, behind views that live outside EditorView.
    static let editorBackground = Color(red: 0.065, green: 0.07, blue: 0.08)
}

extension NSColor {
    static let editorBackground = NSColor(red: 0.065, green: 0.07, blue: 0.08, alpha: 1)
}

/// A window beside the editor (batch, detached agent dock, Knowledge, plugin views). It lives outside EditorView, so
/// it takes the editor's dark appearance, background and tint itself.
@MainActor
enum AuxiliaryWindow {
    /// A titled, resizable window holding `content`, kept when closed. It keeps its own size: wrapping text measured
    /// at a narrow width would otherwise grow it. The caller sets its delegate, places and shows it.
    static func make(title: String, size: NSSize, minSize: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .editorBackground
        let hosting = NSHostingView(rootView: content.background(Color.editorBackground)
            .preferredColorScheme(.dark).tint(.cyan))
        hosting.sizingOptions = []
        window.contentView = hosting
        return window
    }
}
