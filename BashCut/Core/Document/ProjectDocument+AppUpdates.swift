import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import Foundation

extension ProjectDocument {
    /// A newer release is known and the user has not put it off with Later.
    var showsAppUpdateNotice: Bool {
        guard let release = appUpdate.available else { return false }
        return settings.appUpdateDismissed != release.version
    }

    /// The daily check when a project opens. A newer release (found now or by an earlier check) opens Software Update
    /// once per launch, unless it was skipped or put off with Remind Me Later.
    func checkAppUpdateIfDue() {
        Task { @MainActor in
            await appUpdate.checkIfDue()
            promptForAppUpdateIfDue()
        }
    }

    func promptForAppUpdateIfDue(now: Date = Date()) {
        guard Self.appUpdatePromptPending, appUpdate.install == .homebrew || appUpdate.install == .direct,
              showsAppUpdateNotice, !ui.showUpdates
        else { return }
        if let remindAfter = settings.appUpdateRemindAfter, now < remindAfter { return }
        Self.appUpdatePromptPending = false
        settings.appUpdateRemindAfter = nil
        ui.updatesPrompt = true
        ui.showUpdates = true
    }

    /// Update Now (Homebrew copies): Homebrew downloads the new release while BashCut runs, then BashCut saves the
    /// project, starts the helper and quits; the helper upgrades the cask and opens the new version. A failure on
    /// the way leaves BashCut running and shows why in Software Update.
    func installAppUpdate() {
        guard appUpdate.canInstallNow else { return }
        Task { @MainActor in
            guard await appUpdate.prepareInstall() else { return }
            if dirty {
                guard fileURL != nil else {
                    appUpdate.cancelInstall(String(localized: "Save the project first, then update"))
                    return
                }
                do { try await saveNow() } catch {
                    appUpdate.cancelInstall(String(localized: "The project could not be saved, so BashCut was not updated"))
                    return
                }
            }
            do {
                try appUpdate.startInstaller(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    defaultsDomain: Bundle.main.bundleIdentifier ?? "app.bashcut")
            } catch { return }
            DebugLog.write("app", "update: quitting for brew upgrade")
            // AppKit refuses to quit while a sheet is up, Software Update included.
            ui.showUpdates = false
            try? await Task.sleep(for: .milliseconds(500))
            // Not from this task: quitting waits for a main-actor reply (terminateLater), which cannot run while a
            // main-queue job is still inside terminate.
            RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            // Still here: quitting was refused (an export or a save is running), so the helper is stopped.
            try? await Task.sleep(for: .seconds(30))
            appUpdate.cancelInstall(String(localized: "BashCut did not quit, so it was not updated"))
        }
    }

    /// Why `app update` cannot run now, or nil when it can.
    private var appUpdateBlocker: String? {
        if appUpdate.canInstallNow { return nil }
        if appUpdate.available == nil { return "No newer BashCut release is known; run app update-check first" }
        if appUpdate.install != .homebrew {
            return "Only a Homebrew copy updates itself; this one is \(appUpdate.install.rawValue)"
        }
        if !appUpdate.updatesItself { return "Homebrew (brew) was not found" }
        return "An update is already under way"
    }

    /// The prompt opens at most once per launch, also with several windows or project switches.
    @MainActor static var appUpdatePromptPending = true

    /// Software Update for `ui dialog` / `ui respond`; with a new release, the prompt's Skip This Version and
    /// Remind Me Later.
    func appUpdateSheet() -> ModalSheet? {
        guard ui.showUpdates else { return nil }
        let release = showsAppUpdateNotice ? appUpdate.available : nil
        return ModalSheet(
            name: "updates", title: "Software update",
            message: release.map { "BashCut \($0.version) is available; this is \(appUpdate.version)" },
            options: (release != nil && appUpdate.canInstallNow ? [ModalOption("update", String(localized: "Update Now"))] : [])
                + (release == nil ? [] : [
                ModalOption("skip", String(localized: "Skip This Version")),
                ModalOption("later", String(localized: "Remind Me Later")),
            ]) + [ModalOption("close", String(localized: "Close"))]
        ) { [weak self] option in
            guard let self else { return }
            switch option {
            case "update": installAppUpdate()
            case "skip": run(.skipAppUpdate)
            case "later": run(.remindAppUpdateLater)
            default: ui.showUpdates = false
            }
        }
    }

    func registerAppCommands() {
        handle("app.version") { document, _, _ in
            let update = document.appUpdate
            return .object([
                "version": .string(update.version), "build": .string(update.build),
                "install": .string(update.install.rawValue), "pluginAPI": .integer(PluginAPI.current),
            ])
        }
        handle("app.update-check") { document, _, _ in
            await document.appUpdate.check()
            return document.appUpdate.fields
        }
        handleAuthored("app.update") { document, _, author in
            if let blocker = document.appUpdateBlocker { throw RPCFailure(-32602, blocker) }
            let update = document.appUpdate
            let approval = try document.queuePrivilegedApproval(
                method: "app.update", author: author,
                arguments: ["from": update.version, "to": update.available?.version ?? "", "command": AppUpdateModel.homebrewCommand]
            ) { [weak document] in
                document?.ui.showUpdates = true
                document?.installAppUpdate()
            }
            if !approval.autoApproved {
                document.message = String(localized: "Waiting for approval: app.update")
            }
            return .object([
                "approval": .string(approval.autoApproved ? "approved" : "pending"),
                "requestId": .string(approval.id.uuidString),
                "from": .string(update.version), "to": update.available.map { .string($0.version) } ?? .null,
            ])
        }
    }
}
