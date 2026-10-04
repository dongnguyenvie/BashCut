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
            options: (release == nil ? [] : [
                ModalOption("skip", String(localized: "Skip This Version")),
                ModalOption("later", String(localized: "Remind Me Later")),
            ]) + [ModalOption("close", String(localized: "Close"))]
        ) { [weak self] option in
            guard let self else { return }
            switch option {
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
    }
}
