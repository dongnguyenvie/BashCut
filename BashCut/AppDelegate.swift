import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
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
        VideoDecoders.enable()
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
        // After the launch settles (plugins listed, a project opened from Finder). From a run loop timer, not a main
        // queue block: the alert's modal loop would hold the main queue, and with it every automation call.
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [document] _ in
            MainActor.assumeIsolated { document.offerBatchResume() }
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
        guard !document.saving, !document.busy else { return .terminateCancel }
        if document.batches.active?.state == .running {
            guard confirmQuitDuringBatch() else { return .terminateCancel }
            // Saved interrupted, so the next launch offers to resume it. The open project is the item it was on, whose
            // unsaved steps run again on resume, so it is dropped without asking.
            document.batches.interrupt(jobs: document.jobs)
        } else {
            guard document.confirmDiscard() else { return .terminateCancel }
        }
        if document.privilegedApproval != nil { document.resolvePrivilegedApproval(false) }
        document.resolveScopeHold(.reject, byUser: false)
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
    /// Asks before quitting while a batch runs; it stops where it is and the next launch offers to resume it.
    private func confirmQuitDuringBatch() -> Bool {
        guard let run = document.batches.active, run.state == .running else { return true }
        let done = run.items.filter(\.state.isFinished).count
        let answer = ModalCenter.shared.alert(
            "quit-during-batch", title: String(localized: "A batch is still running"),
            message: String(format: String(localized: "%lld of %lld items are done. Quit now and resume the rest the next time BashCut opens?"),
                            done, run.items.count),
            buttons: [ModalOption("cancel", String(localized: "Keep Running")), ModalOption("quit", String(localized: "Quit"))])
        return answer == "quit"
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
