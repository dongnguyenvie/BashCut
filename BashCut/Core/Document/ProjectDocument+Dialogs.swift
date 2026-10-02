import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Every sheet and popover, so agents can read and answer them with `ui.dialog` / `ui.respond`
/// the way the user would. AppKit alerts and file panels report themselves through `ModalCenter`.
extension ProjectDocument {
    private static let close = ModalOption("close", String(localized: "Close"))

    func registerDialogs() {
        ModalCenter.shared.sheets = { [weak self] in self?.openSheets() ?? [] }
    }

    /// Open sheets and popovers, bottom to top.
    func openSheets() -> [ModalSheet] {
        var sheets: [ModalSheet] = []
        func closing(_ name: String, _ title: String, when open: Bool, _ close: @escaping @MainActor () -> Void) {
            guard open else { return }
            sheets.append(ModalSheet(name: name, title: title, options: [Self.close]) { _ in close() })
        }
        closing("ask", "Ask agent", when: showAsk) { [weak self] in self?.showAsk = false }
        closing("sections", "Sections", when: showSections) { [weak self] in self?.showSections = false }
        closing("new-project", "New project", when: showNewProject) { [weak self] in self?.showNewProject = false }
        closing("export", "Export", when: showExport) { [weak self] in self?.showExport = false }
        closing("export-report", "Export report", when: showExportReport) { [weak self] in
            self?.showExportReport = false
        }
        closing("legacy-import-report", "Legacy EDL import", when: showLegacyImportReport) { [weak self] in
            self?.showLegacyImportReport = false
        }
        closing("review", "Review", when: showReview) { [weak self] in self?.showReview = false }
        closing("history", "History", when: showHistory) { [weak self] in self?.showHistory = false }
        closing("plugins", "Plugins", when: showPlugins) { [weak self] in self?.showPlugins = false }
        closing("settings", "Settings", when: showSettings) { [weak self] in self?.showSettings = false }
        closing("doctor", "Doctor", when: showDoctor) { [weak self] in self?.showDoctor = false }
        closing("knowledge", "Skills and project memory", when: agents.showKnowledge) { [weak self] in
            self?.agents.showKnowledge = false
        }
        if showAgentChanges {
            sheets.append(ModalSheet(
                name: "agent-changes", title: "Agent changes",
                options: [ModalOption("undo", String(localized: "Undo")), Self.close]
            ) { [weak self] option in
                guard let self else { return }
                if option == "undo" { undoAgentChange() }
                showAgentChanges = false
            })
        }
        if showExternalChanges {
            sheets.append(ModalSheet(
                name: "external-changes", title: "The project file changed on disk",
                options: [
                    ModalOption("keep-app", "Keep BashCut version"), ModalOption("load-disk", "Load disk version"),
                    Self.close,
                ]
            ) { [weak self] option in
                guard let self else { return }
                if option == "close" { showExternalChanges = false } else { resolveConflict(loadDisk: option == "load-disk") }
            })
        }
        if showPlugins, let pending = plugins.pendingInstall {
            // Installing runs the plugin's dependency recipes; only the user can approve it.
            sheets.append(ModalSheet(
                name: "plugin-install", title: "Install \(pending.plugin.manifest.name)?",
                message: "Only the user can approve a plugin install.",
                options: [ModalOption("cancel", String(localized: "Cancel"))]
            ) { [weak self] _ in self?.plugins.pendingInstall = nil })
        }
        if let prompt = privilegedApproval {
            // Approving stays with the user; agents can only decline.
            sheets.append(ModalSheet(
                name: "approval", title: "Approve \(prompt.method) from \(prompt.author.rawValue)?",
                message: "Only the user can approve. Turn on Settings → Run agent exports without confirmation "
                    + "to let agents export without asking.",
                options: [ModalOption("deny", String(localized: "Deny"))]
            ) { [weak self] _ in self?.resolvePrivilegedApproval(false) })
        }
        return sheets
    }

    func registerDialogCommands() {
        handle("ui.dialog") { _, _, _ in
            let center = ModalCenter.shared
            return .object([
                "dialog": center.current?.json ?? .null, "open": .array(center.open.map(\.json)),
            ])
        }
        handle("ui.respond") { _, arguments, _ in
            let option = arguments.optionalString("option")
            let path = arguments.optionalString("path").map { URL(fileURLWithPath: $0) }
            guard option != nil || path != nil else { throw RPCFailure(-32602, "Give an option or a path") }
            let center = ModalCenter.shared
            guard let answered = center.current else { throw RPCFailure(-32003, "No dialog is open") }
            do {
                try center.respond(option: option, path: path, dialog: arguments.optionalString("dialog"))
            } catch { throw RPCFailure(-32602, error.localizedDescription) }
            DebugLog.write("ui", "dialog \(answered.name) answered \(option ?? path?.path ?? "")")
            return .object(["answered": answered.json])
        }
        handle("ui.open") { document, arguments, _ in
            if let open = ModalCenter.shared.current {
                throw RPCFailure(-32003, "Close the open dialog \(open.name) first")
            }
            try document.openDialog(try arguments.string("dialog"))
            return .bool(true)
        }
    }

    private static var toggledDialogs: [String: ReferenceWritableKeyPath<ProjectDocument, Bool>] {
        [
            "review": \.showReview, "history": \.showHistory, "plugins": \.showPlugins, "settings": \.showSettings,
            "doctor": \.showDoctor, "ask": \.showAsk, "sections": \.showSections,
        ]
    }

    /// Sheets that only make sense in some states: (available, reason when not, flag).
    private static var conditionalDialogs:
        [String: (available: (ProjectDocument) -> Bool, reason: String, flag: ReferenceWritableKeyPath<ProjectDocument, Bool>)]
    {
        [
            "export": ({ $0.project.duration > 0 }, "The timeline is empty", \.showExport),
            "export-report": ({ $0.exportReport != nil }, "No export report yet", \.showExportReport),
            "agent-changes": ({ $0.agentChange != nil }, "No agent change to show", \.showAgentChanges),
            "external-changes": ({ $0.conflict }, "The project file has no conflicting change", \.showExternalChanges),
        ]
    }

    func openDialog(_ name: String) throws {
        if name == "plugins" { plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent()) }
        if let flag = Self.toggledDialogs[name] {
            self[keyPath: flag] = true
        } else if let dialog = Self.conditionalDialogs[name] {
            guard dialog.available(self) else { throw RPCFailure(-32602, dialog.reason) }
            self[keyPath: dialog.flag] = true
        } else if name == "new-project" {
            newProject()
        } else if name == "knowledge" {
            agents.knowledge.load(from: agents.directory)
            agents.showKnowledge = true
        } else {
            throw RPCFailure(-32602, "Unknown dialog \(name)")
        }
        DebugLog.write("ui", "dialog \(name) opened")
    }
}
