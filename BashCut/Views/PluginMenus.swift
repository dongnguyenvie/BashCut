import AppKit
import BashCutAutomation

/// AppKit menus for plugin actions: the main-menu Plugins menu and entries appended to context menus.
@MainActor enum PluginMenus {
    /// Menu items for the actions at `placement`, enabled by their `when` condition.
    static func items(_ document: ProjectDocument, placement: String, mediaID: String? = nil) -> [NSMenuItem] {
        document.plugins.actions(at: placement).map { action in
            let item = ClosureMenuItem(action.title) { [weak document] in
                document?.triggerPluginAction(action, mediaID: mediaID)
            }
            item.isEnabled = document.canRunPluginAction(action, mediaID: mediaID)
            item.toolTip = action.plugin.manifest.name
            if let icon = action.spec.icon { item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
            return item
        }
    }

    /// Appends the actions at `placement` to `menu` after a separator.
    static func append(to menu: NSMenu, _ document: ProjectDocument, placement: String, mediaID: String? = nil) {
        let entries = items(document, placement: placement, mediaID: mediaID)
        guard !entries.isEmpty else { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        entries.forEach(menu.addItem)
    }

    /// The main-menu Plugins item. Its menu is rebuilt each time it opens, so it follows the catalog.
    static func mainMenuItem(_ document: ProjectDocument) -> NSMenuItem {
        let controller = PluginMainMenuController(document: document)
        let menu = NSMenu(title: String(localized: "Plugins"))
        menu.autoenablesItems = false
        menu.delegate = controller
        controller.rebuild(menu)
        let item = NSMenuItem()
        item.submenu = menu
        // The menu keeps only a weak reference to its delegate.
        objc_setAssociatedObject(menu, &PluginMainMenuController.key, controller, .OBJC_ASSOCIATION_RETAIN)
        return item
    }
}

private final class PluginMainMenuController: NSObject, NSMenuDelegate {
    nonisolated(unsafe) static var key = 0
    weak var document: ProjectDocument?

    init(document: ProjectDocument) { self.document = document }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild(menu) }
    }

    @MainActor func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let document else { return }
        menu.addItem(ClosureMenuItem(String(localized: "Manage Plugins…")) { [weak document] in
            document?.run(.showPlugins)
        })
        if !document.plugins.proposals.isEmpty {
            let title = String(format: String(localized: "Review Plugin Edits (%d)"), document.plugins.proposals.count)
            menu.addItem(ClosureMenuItem(title) { [weak document] in document?.ui.showPluginProposals = true })
        }
        var currentPlugin: String?
        for action in document.plugins.actions(at: "menu.plugins") {
            if action.plugin.id != currentPlugin {
                currentPlugin = action.plugin.id
                menu.addItem(.separator())
                let header = NSMenuItem(title: action.plugin.manifest.name, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
            let item = ClosureMenuItem(action.title) { [weak document] in document?.triggerPluginAction(action) }
            item.isEnabled = document.canRunPluginAction(action)
            if let icon = action.spec.icon { item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
            if let shortcut = action.shortcut, shortcut.key.count == 1 {
                item.keyEquivalent = shortcut.key
                var mask: NSEvent.ModifierFlags = []
                if shortcut.modifiers.contains(.command) { mask.insert(.command) }
                if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
                if shortcut.modifiers.contains(.option) { mask.insert(.option) }
                if shortcut.modifiers.contains(.control) { mask.insert(.control) }
                item.keyEquivalentModifierMask = mask
            }
            menu.addItem(item)
        }
    }
}
