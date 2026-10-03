import AppKit

/// Editing commands for the embedded terminals. The menu bar's Edit menu (`MainMenu`) carries the same
/// nil-targeted Cut/Copy/Paste/Select All, which ⌘X/⌘C/⌘V/⌘A need to reach text fields and terminals.
@MainActor enum EditMenus {
    /// Right-click menu for a terminal, targeted at that terminal even when another view has focus.
    static func terminalContextMenu(for view: NSView) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            (String(localized: "Copy"), #selector(NSText.copy(_:))),
            (String(localized: "Paste"), #selector(NSText.paste(_:))),
            (String(localized: "Select All"), #selector(NSText.selectAll(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = view
            menu.addItem(item)
        }
        return menu
    }
}
