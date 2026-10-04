import BashCutAutomation
import SwiftUI

extension View {
    /// Binds the action's shortcut from `UIAction`, so the UI and `ui.actions` never disagree.
    @ViewBuilder
    func shortcut(_ action: UIAction) -> some View {
        if let shortcut = action.shortcut?.keyboardShortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }

    /// Shortcut plus enabled state for an editor action button.
    func action(_ action: UIAction, in document: ProjectDocument) -> some View {
        shortcut(action).disabled(!document.canPerform(action))
    }
}

extension UIShortcut {
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch self.key {
        case "space": key = .space
        case "delete": key = .delete
        case "escape": key = .escape
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        default:
            guard self.key.count == 1, let character = self.key.first else { return nil }
            key = KeyEquivalent(character)
        }
        var flags: EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return KeyboardShortcut(key, modifiers: flags)
    }
}
