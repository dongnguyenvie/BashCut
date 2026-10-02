import AppKit

/// Standard macOS editing commands. Without an Edit menu, ⌘C/⌘V/⌘X/⌘A never reach text fields or the
/// embedded terminals, because AppKit routes those shortcuts through menu key equivalents.
@MainActor enum EditMenus {
    /// The main-menu Edit item. Actions are nil-targeted, so they go to whichever view has focus.
    /// Undo/Redo stay with the timeline's own ⌘Z buttons.
    static func mainMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

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
