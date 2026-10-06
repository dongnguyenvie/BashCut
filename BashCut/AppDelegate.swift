import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutStorage
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let document = ProjectDocument(services: .live())
    private var window: NSWindow?
    /// Target of the menu bar items; NSMenu keeps only weak references to them.
    private var mainMenu: MainMenu?
    /// A project Finder asked to open before the window existed.
    private var pendingOpen: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let executable = Bundle.main.executableURL
        let built = executable.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        DebugLog.write(
            "app", "launch pid=\(ProcessInfo.processInfo.processIdentifier) executable=\(executable?.path ?? "?") "
                + "built=\(built.map { "\($0)" } ?? "?") log=\(DebugLog.url.path)")
        document.startAutomation()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "BashCut"
        // The editor's toolbar sits in the title bar, next to the close, minimize and zoom buttons.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: EditorView(document: document))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        mainMenu = MainMenu.install(document)
        NSApp.activate(ignoringOtherApps: true)
        if let pendingOpen {
            self.pendingOpen = nil
            open(pendingOpen)
        }
    }

    /// Finder: double-click or "Open With" on a project file, or a project file or folder dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        DebugLog.write("app", "open from Finder \(url.path)")
        if window == nil { pendingOpen = url } else { open(url) }
    }

    private func open(_ url: URL) {
        window?.makeKeyAndOrderFront(nil)
        guard let file = ProjectStorage.projectFile(for: url) else {
            document.message = String(localized: "No BashCut project in that folder")
            return
        }
        // A file panel or alert may be up; open once the current modal session ends.
        RunLoop.main.perform(inModes: [.default]) { [document] in
            MainActor.assumeIsolated { document.openProject(at: file) }
        }
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
        document.resolveScopeHold(.reject)
        document.agents.closeAll()
        document.removeExternalAgentToken()
        Task {
            do {
                if document.dirty, let url = document.fileURL {
                    try await document.storage.discardRecovery(at: url)
                }
                await document.automation.stop()
                await PluginSessionTransport.shared.stopAll()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                document.message = error.localizedDescription
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    /// The close button and ⌘W work in two steps: with a project open they close it (saving first) and show the
    /// Welcome screen; on the Welcome screen they quit. ⌘Q always quits.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if document.fileURL != nil {
            document.run(.closeProject)
        } else {
            NSApp.terminate(nil)
        }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
