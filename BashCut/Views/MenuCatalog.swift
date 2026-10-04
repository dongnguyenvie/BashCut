import AppKit
import BashCutAutomation

/// The menu bar read back as data for the command palette and the keyboard-shortcuts sheet. Both list exactly
/// what the menus have, so a command or shortcut never shows up in one place and not the other.
@MainActor enum MenuCatalog {
    struct Entry: Identifiable {
        /// The menu item's identity: two items can share a path and title (recent projects in two folders).
        var id: ObjectIdentifier { ObjectIdentifier(item) }
        /// The menu path and title, e.g. `Clip ▸ Speed ▸ Speed Up`; what the palette searches.
        let text: String
        /// Menus above the item, from the menu bar down.
        let path: [String]
        let title: String
        /// The shortcut as the menu shows it (`⇧⌘P`), or empty.
        let shortcut: String
        let enabled: Bool
        fileprivate let item: NSMenuItem

        /// Runs the item the way choosing it in the menu would.
        @MainActor func run() {
            if let entry = item as? ActionMenuItem {
                entry.handler()
            } else if let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        }
    }

    /// Every item of the menu bar that runs something. Menus filled when they open (Open Recent, New Tab,
    /// Plugins) are filled first, so their current entries are included.
    static func entries() -> [Entry] {
        guard let menu = NSApp.mainMenu else { return [] }
        var entries: [Entry] = []
        for top in menu.items {
            guard let submenu = top.submenu else { continue }
            collect(submenu, path: [top.submenu?.title ?? top.title], into: &entries)
        }
        return entries
    }

    private static func collect(_ menu: NSMenu, path: [String], into entries: inout [Entry]) {
        menu.delegate?.menuNeedsUpdate?(menu)
        // Alternates (shown while ⌥ is held, like Quit and Keep Windows) belong to the item before them.
        for item in menu.items where !item.isSeparatorItem && !item.isHidden && !item.isAlternate && !item.title.isEmpty {
            if let submenu = item.submenu {
                if submenu !== NSApp.servicesMenu { collect(submenu, path: path + [item.title], into: &entries) }
                continue
            }
            guard item.action != nil else { continue }
            let enabled = (item as? ActionMenuItem).map { $0.isAvailable?() ?? true } ?? item.isEnabled
            entries.append(Entry(
                text: (path + [item.title]).joined(separator: " ▸ "), path: path, title: item.title,
                shortcut: label(item), enabled: enabled, item: item))
        }
    }

    /// Entries whose path or title contains every word of `query`, ignoring case and Vietnamese marks;
    /// titles that start with the query come first.
    static func filter(_ entries: [Entry], _ query: String) -> [Entry] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return entries }
        let first = words.joined(separator: " ")
        return entries
            .filter { entry in
                let text = fold(entry.text)
                return words.allSatisfy(text.contains)
            }
            .sorted { lhs, rhs in
                let left = fold(lhs.title).hasPrefix(first), right = fold(rhs.title).hasPrefix(first)
                if left != right { return left }
                return lhs.enabled && !rhs.enabled
            }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: "đ", with: "d")
    }

    /// `⌃⌥⇧⌘` and the key, the way macOS menus draw a key equivalent.
    static func label(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let mask = item.keyEquivalentModifierMask
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + keyName(item.keyEquivalent)
    }

    static func label(_ shortcut: UIShortcut) -> String {
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        let names = ["space": "Space", "delete": "⌫", "escape": "Esc", "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return text + (names[shortcut.key] ?? shortcut.key.uppercased())
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return key }
        switch Int(scalar.value) {
        case 0x20: return "Space"
        case 0x1b: return "Esc"
        case NSBackspaceCharacter, NSDeleteCharacter: return "⌫"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        default: return key.uppercased()
        }
    }

    /// Keys that work only while the timeline has keyboard focus: an action's shortcuts after the one its menu
    /// item shows (`S` splits, like ⌘B).
    static var timelineKeys: [(title: String, shortcut: String)] {
        UIAction.allCases.flatMap { action in
            action.shortcuts.dropFirst().map { (action.title, label($0)) }
        }
    }
}
