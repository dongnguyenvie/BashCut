import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let document = ProjectDocument()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        document.startAutomation()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "BashCut"
        window.contentView = NSHostingView(rootView: EditorView(document: document))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "Quit BashCut"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidResignActive(_ notification: Notification) { document.autosave() }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await document.checkExternalFile() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !document.saving, !document.busy, document.confirmDiscard() else {
            return .terminateCancel
        }
        if document.privilegedApproval != nil { document.resolvePrivilegedApproval(false) }
        document.agents.closeAll()
        Task {
            do {
                if document.dirty, let url = document.fileURL {
                    try await document.storage.discardRecovery(at: url)
                }
                await document.automationServer.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                document.message = error.localizedDescription
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
