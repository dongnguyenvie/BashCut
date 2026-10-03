import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin

/// The macOS menu bar: every editor action with its shortcut, in the standard Mac order (app, File, Edit,
/// Clip, Timeline, Playback, View, Agent, Plugins, Window, Help). Items run through `ProjectDocument.run(_:)`,
/// so the menu bar, the editor's buttons and `ui.action` share one code path and one shortcut table.
@MainActor final class MainMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private unowned let document: ProjectDocument
    /// Open menus. Shortcuts without ⌘, ⌥ or ⌃ (Space, I, ←, ⌫) are shown on their items but only run
    /// from a click: typed, they belong to the focused text field or to the timeline's own key handling.
    private var openMenus = 0

    private init(document: ProjectDocument) { self.document = document }

    /// Builds the main menu. The returned object must stay alive as long as the menu: it is every item's target.
    static func install(_ document: ProjectDocument) -> MainMenu {
        let controller = MainMenu(document: document)
        let menu = NSMenu()
        for item in [
            controller.appMenu(), controller.fileMenu(), controller.editMenu(), controller.clipMenu(),
            controller.timelineMenu(), controller.playbackMenu(), controller.viewMenu(), controller.agentMenu(),
            PluginMenus.mainMenuItem(document), controller.windowMenu(), controller.helpMenu(),
        ] {
            if let submenu = item.submenu, submenu.delegate == nil { submenu.delegate = controller }
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
        return controller
    }

    // MARK: Menus

    private func appMenu() -> NSMenuItem {
        let menu = NSMenu(title: "BashCut")
        menu.addItem(ActionMenuItem(String(localized: "About BashCut"), target: self) { MainMenu.showAbout() })
        menu.addItem(.separator())
        menu.addItem(item(.showSettings, String(localized: "Settings…")))
        menu.addItem(item(.showDoctor, String(localized: "Check Setup (Doctor)…")))
        menu.addItem(.separator())
        let services = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Hide BashCut"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = menu.addItem(
            withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit BashCut"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return wrap(menu)
    }

    private func fileMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(item(.newProject, String(localized: "New Project…")))
        menu.addItem(item(.openProject, String(localized: "Open Project…")))
        let recent = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "")
        recent.submenu = DynamicMenu(String(localized: "Open Recent")) { [weak self] menu in self?.fillRecents(menu) }
        menu.addItem(recent)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(item(.saveProject, String(localized: "Save")))
        menu.addItem(item(.importMedia, String(localized: "Import Footage…")))
        menu.addItem(.separator())
        menu.addItem(item(.showReview, String(localized: "Review Before Export…")))
        menu.addItem(item(.showExport, String(localized: "Export…")))
        menu.addItem(item(.openExportOutput, String(localized: "Open Last Export")))
        menu.addItem(item(.revealExportOutput, String(localized: "Reveal Last Export in Finder")))
        menu.addItem(ActionMenuItem(
            String(localized: "Export Report…"), target: self,
            enabled: { [weak self] in self?.document.exports.report != nil },
            handler: { [weak self] in self?.document.ui.showExportReport = true }))
        return wrap(menu)
    }

    private func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(item(.undo, String(localized: "Undo")))
        menu.addItem(item(.redo, String(localized: "Redo")))
        menu.addItem(item(.showHistory, String(localized: "History…")))
        menu.addItem(.separator())
        // Nil-targeted, so they reach whichever view has focus: text fields and the embedded terminals.
        menu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(item(.delete, String(localized: "Delete (Ripple)")))
        menu.addItem(item(.lift, String(localized: "Lift (Leave Gap)")))
        return wrap(menu)
    }

    private func clipMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Clip"))
        menu.addItem(item(.split, String(localized: "Split at Playhead")))
        menu.addItem(item(.freezeFrame, String(localized: "Freeze Frame")))
        menu.addItem(item(.changeFraming, String(localized: "Change Framing")))
        menu.addItem(.separator())
        let speed = NSMenu(title: String(localized: "Speed"))
        speed.addItem(item(.speedUp, String(localized: "Speed Up")))
        speed.addItem(item(.slowDown, String(localized: "Slow Down")))
        speed.addItem(.separator())
        speed.addItem(item(.resetSpeed, String(localized: "Normal Speed")))
        menu.addItem(submenu(speed))
        menu.addItem(item(.unlinkAudio, String(localized: "Unlink Audio")))
        menu.addItem(.separator())
        menu.addItem(item(.askAgent, String(localized: "Ask Agent About Selection…")))
        return wrap(menu)
    }

    private func timelineMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Timeline"))
        let layers = NSMenu(title: String(localized: "Add Layer"))
        layers.addItem(item(.addVideoLayer, String(localized: "Video Layer")))
        layers.addItem(item(.addAdjustmentLayer, String(localized: "Adjustment Layer")))
        layers.addItem(item(.addTextLayer, String(localized: "Text Layer")))
        layers.addItem(item(.addAudioLayer, String(localized: "Audio Layer")))
        menu.addItem(submenu(layers))
        menu.addItem(item(.layerUp, String(localized: "Move Layer Up")))
        menu.addItem(item(.layerDown, String(localized: "Move Layer Down")))
        menu.addItem(item(.deleteLayer, String(localized: "Delete Empty Layer")))
        menu.addItem(.separator())
        menu.addItem(item(.toggleSnap, String(localized: "Snap")) { [weak self] in self?.document.ui.snapping == true })
        menu.addItem(item(.showSections, String(localized: "Sections…")))
        menu.addItem(item(.refreshWaveforms, String(localized: "Refresh Waveforms")))
        menu.addItem(.separator())
        menu.addItem(item(.zoomIn, String(localized: "Zoom In")))
        menu.addItem(item(.zoomOut, String(localized: "Zoom Out")))
        menu.addItem(item(.zoomFit, String(localized: "Zoom to Fit")))
        return wrap(menu)
    }

    private func playbackMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Playback"))
        // One item for both viewers: the source viewer's action while it is shown, else the timeline's.
        menu.addItem(item(.togglePlayback, or: .sourceTogglePlayback, String(localized: "Play / Pause")))
        menu.addItem(.separator())
        menu.addItem(item(.previousFrame, or: .sourcePreviousFrame, String(localized: "Previous Frame")))
        menu.addItem(item(.nextFrame, or: .sourceNextFrame, String(localized: "Next Frame")))
        menu.addItem(item(.backSecond, String(localized: "Back 1 Second")))
        menu.addItem(item(.forwardSecond, String(localized: "Forward 1 Second")))
        menu.addItem(.separator())
        menu.addItem(header(String(localized: "Source Viewer")))
        menu.addItem(item(.markIn, String(localized: "Mark In")))
        menu.addItem(item(.markOut, String(localized: "Mark Out")))
        menu.addItem(item(.sourceInsert, String(localized: "Insert at Playhead")))
        menu.addItem(item(.sourceOverwrite, String(localized: "Overwrite at Playhead")))
        menu.addItem(item(.sourceClose, String(localized: "Close Source Viewer")))
        return wrap(menu)
    }

    private func viewMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "View"))
        let library = NSMenu(title: String(localized: "Library"))
        for (index, tab) in LibraryTab.allCases.enumerated() {
            let entry = ActionMenuItem(
                String(localized: String.LocalizationValue(tab.rawValue)), target: self,
                checked: { [weak self] in self?.document.ui.libraryTab == tab },
                handler: { [weak self] in self?.document.showLibraryTab(tab) })
            if index < 9 {
                entry.keyEquivalent = String(index + 1)
                entry.keyEquivalentModifierMask = .command
            }
            entry.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil)
            library.addItem(entry)
        }
        menu.addItem(submenu(library))
        menu.addItem(.separator())
        menu.addItem(item(.toggleSafeArea, String(localized: "Safe Area")) { [weak self] in
            self?.document.ui.showSafeArea == true
        })
        menu.addItem(item(.toggleCompare, String(localized: "Compare Before / After")) { [weak self] in
            self?.document.preview.showColorComparison == true
        })
        menu.addItem(.separator())
        menu.addItem(item(.toggleAgentDock, String(localized: "Agent Dock")) { [weak self] in
            guard let self else { return false }
            return document.ui.showAgentDock && !document.agents.isDetached
        })
        menu.addItem(.separator())
        menu.addItem(item(.showCommands, String(localized: "Command Palette…")))
        let fullScreen = menu.addItem(
            withTitle: String(localized: "Enter Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return wrap(menu)
    }

    private func agentMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Agent"))
        menu.addItem(item(.askAgent, String(localized: "Ask Agent…")))
        let tabs = NSMenuItem(title: String(localized: "New Tab"), action: nil, keyEquivalent: "")
        tabs.submenu = DynamicMenu(String(localized: "New Tab")) { [weak self] menu in self?.fillAgentTabs(menu) }
        menu.addItem(tabs)
        menu.addItem(.separator())
        menu.addItem(item(.showAgentChanges, String(localized: "Show Agent Changes")))
        menu.addItem(item(.undoAgentChange, String(localized: "Undo Agent Change")))
        return wrap(menu)
    }

    private func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(
            withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "")
        NSApp.windowsMenu = menu
        return wrap(menu)
    }

    private func helpMenu() -> NSMenuItem {
        let menu = NSMenu(title: String(localized: "Help"))
        let links = AppLinks.current
        menu.addItem(item(.showShortcuts, String(localized: "Keyboard Shortcuts…")))
        menu.addItem(.separator())
        if let repository = links.repository {
            menu.addItem(link(String(localized: "BashCut on GitHub"), repository))
            menu.addItem(link(String(localized: "Plugin Guide"), repository.appending(path: "blob/main/docs/guides/plugins.md")))
        }
        if let issues = links.issues { menu.addItem(link(String(localized: "Report an Issue…"), issues)) }
        if let email = links.contactEmail, let url = URL(string: "mailto:\(email)") {
            menu.addItem(link(String(localized: "Contact Support…"), url))
        }
        menu.addItem(.separator())
        menu.addItem(item(.showDoctor, String(localized: "Run Doctor…"), shortcut: false))
        menu.addItem(ActionMenuItem(String(localized: "Open Logs Folder"), target: self) {
            NSWorkspace.shared.activateFileViewerSelecting([DebugLog.url])
        })
        NSApp.helpMenu = menu
        return wrap(menu)
    }

    // MARK: Dynamic content

    private func fillRecents(_ menu: NSMenu) {
        for url in document.settings.recentProjects {
            let entry = ActionMenuItem(url.deletingLastPathComponent().lastPathComponent, target: self) { [weak self] in
                self?.document.openProject(at: url)
            }
            entry.toolTip = url.deletingLastPathComponent().path
            menu.addItem(entry)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(item(.clearRecentProjects, String(localized: "Clear Menu")))
    }

    private func fillAgentTabs(_ menu: NSMenu) {
        let chats = document.chatAgents.available
        if !chats.isEmpty {
            menu.addItem(header(String(localized: "Chat agents")))
            for chat in chats {
                let pluginID = chat.pluginID
                menu.addItem(ActionMenuItem(chat.title, target: self) { [weak self] in
                    guard let self else { return }
                    if !document.agents.isDetached { document.ui.showAgentDock = true }
                    document.agents.openChat(pluginID)
                })
            }
            menu.addItem(.separator())
        }
        menu.addItem(item(.openClaudeTerminal, String(localized: "Claude Terminal")))
        menu.addItem(item(.openCodexTerminal, String(localized: "Codex Terminal")))
        menu.addItem(item(.openShellTerminal, String(localized: "Shell")))
    }

    /// The standard About panel with the plugin API version and the project links.
    static func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        let links = AppLinks.current
        let credits = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        func line(_ label: String, _ text: String, _ url: URL?) {
            if credits.length > 0 { credits.append(NSAttributedString(string: "\n", attributes: attributes)) }
            credits.append(NSAttributedString(string: label + ": ", attributes: attributes))
            var value = attributes
            if let url { value[.link] = url }
            credits.append(NSAttributedString(string: text, attributes: value))
        }
        line(String(localized: "Plugin API"), String(PluginAPI.current), nil)
        // `github.com/owner/repo`: short enough to stay on one line in the panel.
        func short(_ url: URL) -> String { url.host().map { $0 + url.path() } ?? url.absoluteString }
        if let repository = links.repository { line(String(localized: "Repository"), short(repository), repository) }
        if let issues = links.issues { line(String(localized: "Issues"), short(issues), issues) }
        if let email = links.contactEmail { line(String(localized: "Contact"), email, URL(string: "mailto:\(email)")) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        options[.credits] = credits
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Item helpers

    private func wrap(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        menu.delegate = self
        return wrap(menu)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func link(_ title: String, _ url: URL) -> NSMenuItem {
        ActionMenuItem(title, target: self) { NSWorkspace.shared.open(url) }
    }

    /// An item for `action` with the shortcut `UIAction` declares; `checked` shows a check mark.
    private func item(
        _ action: UIAction, _ title: String, shortcut: Bool = true, checked: (() -> Bool)? = nil
    ) -> ActionMenuItem {
        let entry = ActionMenuItem(
            title, target: self, enabled: { [weak self] in self?.document.canPerform(action) == true }, checked: checked,
            handler: { [weak self] in self?.document.run(action) })
        if shortcut, let key = action.shortcut { entry.bind(key) }
        entry.toolTip = action.title
        return entry
    }

    /// An item that runs `primary`, or `fallback` when only that one is available (timeline vs. source viewer).
    private func item(_ primary: UIAction, or fallback: UIAction, _ title: String) -> ActionMenuItem {
        let pick: () -> UIAction? = { [weak self] in
            guard let self else { return nil }
            return [primary, fallback].first(where: document.canPerform)
        }
        let entry = ActionMenuItem(
            title, target: self, enabled: { pick() != nil },
            handler: { [weak self] in if let action = pick() { self?.document.run(action) } })
        if let key = primary.shortcut { entry.bind(key) }
        entry.toolTip = primary.title
        return entry
    }

    // MARK: NSMenuDelegate, NSMenuItemValidation

    func menuWillOpen(_ menu: NSMenu) { openMenus += 1 }
    func menuDidClose(_ menu: NSMenu) { openMenus = max(0, openMenus - 1) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let entry = menuItem as? ActionMenuItem else { return true }
        if let checked = entry.checked { entry.state = checked() ? .on : .off }
        if entry.plainKey && openMenus == 0 { return false }
        // A sheet (Export, Settings, Doctor…) owns the window until it closes, like the toolbar buttons.
        if NSApp.mainWindow?.attachedSheet != nil, entry.blockedBySheet { return false }
        return entry.isAvailable?() ?? true
    }

    @objc fileprivate func runItem(_ sender: ActionMenuItem) { sender.handler() }
}

/// A menu item with a closure; its enabled and check-mark state are read when the menu validates.
@MainActor final class ActionMenuItem: NSMenuItem {
    let handler: () -> Void
    let isAvailable: (() -> Bool)?
    let checked: (() -> Bool)?
    /// The shortcut has no ⌘, ⌥ or ⌃: shown, but typed keys go to the focused view.
    private(set) var plainKey = false
    /// Links and About stay available while a sheet is open; editor actions do not.
    var blockedBySheet: Bool { isAvailable != nil }

    init(
        _ title: String, target: MainMenu, enabled: (() -> Bool)? = nil, checked: (() -> Bool)? = nil,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        self.isAvailable = enabled
        self.checked = checked
        super.init(title: title, action: #selector(MainMenu.runItem(_:)), keyEquivalent: "")
        self.target = target
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func bind(_ shortcut: UIShortcut) {
        let keys: [String: Int] = [
            "space": 0x20, "delete": NSBackspaceCharacter, "left": NSLeftArrowFunctionKey,
            "right": NSRightArrowFunctionKey, "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey,
        ]
        if let code = keys[shortcut.key], let scalar = Unicode.Scalar(code) {
            keyEquivalent = String(Character(scalar))
        } else {
            guard shortcut.key.count == 1 else { return }
            keyEquivalent = shortcut.key
        }
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        keyEquivalentModifierMask = mask
        plainKey = mask.isDisjoint(with: [.command, .option, .control])
    }
}

/// A submenu whose items are rebuilt each time it opens (recent projects, chat agents).
@MainActor final class DynamicMenu: NSMenu, NSMenuDelegate {
    private let fill: (NSMenu) -> Void

    init(_ title: String, fill: @escaping (NSMenu) -> Void) {
        self.fill = fill
        super.init(title: title)
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }
}

/// Project links shown in Help and About, read from Info.plist so they are not hard-coded in views.
/// Keys: `BCRepositoryURL`, `BCIssuesURL`, `BCContactEmail`; a missing or empty key hides its item.
struct AppLinks {
    var repository: URL?
    var issues: URL?
    var contactEmail: String?

    static var current: AppLinks {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            (info[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        return AppLinks(
            repository: value("BCRepositoryURL").flatMap(URL.init(string:)),
            issues: value("BCIssuesURL").flatMap(URL.init(string:)),
            contactEmail: value("BCContactEmail"))
    }
}
