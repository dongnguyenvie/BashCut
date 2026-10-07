import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
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
    /// The Ask agent sheet: `send` sends the draft to the open agent, `clear` empties it.
    private func askSheet() -> ModalSheet? {
        guard ui.showAsk else { return nil }
        let draft = agents.askModel.draft
        return ModalSheet(
            name: "ask", title: "Ask agent", message: draft.isEmpty ? nil : draft,
            options: [ModalOption("send", String(localized: "Send")), ModalOption("clear", String(localized: "Clear")), Self.close]
        ) { [weak self] option in
            guard let self else { return }
            switch option {
            case "send":
                // Like the disabled Send button: refuse instead of answering with nothing sent.
                guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ModalError("The request is empty; write it in the sheet first")
                }
                guard agents.hasOpenAgent else { throw ModalError("Open an agent in the dock first") }
                Task { await self.agents.sendAsk() }
            case "clear": agents.askModel.draft = ""
            default: ui.showAsk = false
            }
        }
    }

    func openSheets() -> [ModalSheet] {
        var sheets: [ModalSheet] = []
        func closing(_ name: String, _ title: String, when open: Bool, _ close: @escaping @MainActor () -> Void) {
            guard open else { return }
            sheets.append(ModalSheet(name: name, title: title, options: [Self.close]) { _ in close() })
        }
        sheets.append(contentsOf: [askSheet(), libraryEditorSheet(), effectApplySheet(), librarySearchSheet()].compactMap { $0 })
        closing("sections", "Sections", when: ui.showSections) { [weak self] in self?.ui.showSections = false }
        closing("commands", "Command palette", when: ui.showCommands) { [weak self] in self?.ui.showCommands = false }
        closing("shortcuts", "Keyboard shortcuts", when: ui.showShortcuts) { [weak self] in
            self?.ui.showShortcuts = false
        }
        closing("new-project", "New project", when: ui.showNewProject) { [weak self] in self?.ui.showNewProject = false }
        closing("export", "Export", when: ui.showExport) { [weak self] in self?.ui.showExport = false }
        if let progress = exportProgressSheet() { sheets.append(progress) }
        closing("export-report", "Export report", when: ui.showExportReport) { [weak self] in
            self?.ui.showExportReport = false
        }
        closing("legacy-import-report", "Legacy EDL import", when: ui.showLegacyImportReport) { [weak self] in
            self?.ui.showLegacyImportReport = false
        }
        closing("review", "Review", when: ui.showReview) { [weak self] in self?.ui.showReview = false }
        closing("history", "History", when: ui.showHistory) { [weak self] in self?.ui.showHistory = false }
        closing("plugins", "Plugins", when: ui.showPlugins) { [weak self] in self?.ui.showPlugins = false }
        closing("settings", "Settings", when: ui.showSettings) { [weak self] in self?.ui.showSettings = false }
        closing("doctor", "Doctor", when: ui.showDoctor) { [weak self] in self?.ui.showDoctor = false }
        if let updates = appUpdateSheet() { sheets.append(updates) }
        closing("knowledge", "Knowledge", when: agents.showKnowledge) { [weak self] in
            self?.agents.closeKnowledge()
        }
        if ui.showAgentChanges {
            sheets.append(ModalSheet(
                name: "agent-changes", title: "Agent changes",
                options: [ModalOption("undo", String(localized: "Undo")), Self.close]
            ) { [weak self] option in
                guard let self else { return }
                if option == "undo" { undoAgentChange() }
                ui.showAgentChanges = false
            })
        }
        if ui.showExternalChanges {
            sheets.append(ModalSheet(
                name: "external-changes", title: "The project file changed on disk",
                options: [
                    ModalOption("keep-app", "Keep BashCut version"), ModalOption("load-disk", "Load disk version"),
                    Self.close,
                ]
            ) { [weak self] option in
                guard let self else { return }
                if option == "close" { ui.showExternalChanges = false } else { resolveConflict(loadDisk: option == "load-disk") }
            })
        }
        if ui.showPlugins, let pending = plugins.pendingInstall {
            // Installing runs the plugin's dependency recipes; only the user can approve it.
            sheets.append(ModalSheet(
                name: "plugin-install",
                title: (pending.repair ? "Set up " : (pending.local == nil ? pending.replacing : plugins.replaces(pending))
                    ? "Update " : "Install ")
                    + pending.plugin.manifest.displayName + "?",
                message: "Only the user can approve a plugin install."
                    + (plugins.mode(of: pending) == .link ? " It is installed as a link (developer mode)." : ""),
                options: [ModalOption("cancel", String(localized: "Cancel"))]
            ) { [weak self] _ in self?.plugins.cancelPendingInstall() })
        }
        sheets += pluginSheets()
        sheets += approvalSheets()
        return sheets
    }

    /// Decisions only the user can approve: a privileged agent action and an edit outside the attached scope.
    private func approvalSheets() -> [ModalSheet] {
        var sheets: [ModalSheet] = []
        if let prompt = privilegedApproval {
            // Approving stays with the user; agents can only decline.
            sheets.append(ModalSheet(
                name: "approval", title: "Approve \(prompt.method) from \(prompt.author.rawValue)?",
                message: "Only the user can approve. Turn on Settings → Run agent exports without confirmation "
                    + "to let agents export without asking.",
                options: [ModalOption("deny", String(localized: "Deny"))]
            ) { [weak self] _ in self?.resolvePrivilegedApproval(false) })
        }
        if let request = checkpoint {
            // Answering stays with the user; an agent can only withdraw its request.
            sheets.append(ModalSheet(
                name: "checkpoint", title: request.gate.label,
                message: "Only the user can approve, ask for changes or reject. " + request.summary,
                options: [ModalOption("withdraw", String(localized: "Withdraw"))]
            ) { [weak self] _ in self?.resolveCheckpoint(.withdrawn) })
        }
        if let hold = scopeHold {
            // Allowing stays with the user; agents can only reject.
            sheets.append(ModalSheet(
                name: "agent-scope", title: "\(hold.agent) wants to edit outside the attached clips",
                message: "This edit also changes: \(hold.outside). Only the user can allow it.",
                options: [ModalOption(AgentScopeChoice.reject.rawValue, String(localized: "Reject"))]
            ) { [weak self] _ in self?.resolveScopeHold(.reject) })
        }
        return sheets
    }

    /// The plugin parameter sheet and the hook-edit review sheet.
    private func pluginSheets() -> [ModalSheet] {
        var sheets: [ModalSheet] = []
        if ui.showPlugins, plugins.showAddPlugin {
            sheets.append(ModalSheet(
                name: "add-plugin", title: "Add Plugin",
                message: "Paste a link or choose a plugin on this Mac (plugins install --url or --path does the same).",
                options: [ModalOption("cancel", String(localized: "Cancel"))]
            ) { [weak self] _ in self?.plugins.showAddPlugin = false })
        }
        if let key = ui.pluginSheet, let (plugin, view) = pluginViews.resolve(key) {
            sheets.append(ModalSheet(
                name: "plugin-view", title: plugin.manifest.displayName + ": " + view.title.text,
                message: "Use plugins view and plugins view-event on \(key) to work in it.", options: [Self.close]
            ) { [weak self] _ in self?.ui.pluginSheet = nil })
        }
        if let pending = plugins.pendingAction {
            sheets.append(ModalSheet(
                name: "plugin-action", title: pending.action.title,
                message: "Runs with the shown parameters; use plugins run --params to set them.",
                options: [ModalOption("run", String(localized: "Run")), ModalOption("cancel", String(localized: "Cancel"))]
            ) { [weak self] option in
                guard let self else { return }
                if option == "run" { runPendingPluginAction() } else { plugins.pendingAction = nil }
            })
        }
        if let pending = plugins.confirmations.first {
            // Running stays with the user; agents can only cancel (or cancel the job).
            sheets.append(ModalSheet(
                name: "plugin-confirm", title: pending.action.title, message: pending.action.spec.confirm?.text,
                options: [ModalOption("cancel", String(localized: "Cancel"))]
            ) { [weak self] _ in self?.resolvePluginConfirm(pending.id, run: false) })
        }
        if ui.showPluginProposals, let proposal = plugins.proposals.first {
            sheets.append(ModalSheet(
                name: "plugin-proposals", title: "\(proposal.plugin.manifest.displayName) proposes: \(proposal.title)",
                message: "\(proposal.proposal.operations.count) operations after \(proposal.event)",
                options: [
                    ModalOption("apply", String(localized: "Apply")), ModalOption("discard", String(localized: "Discard")),
                    Self.close,
                ]
            ) { [weak self] option in
                guard let self else { return }
                if option == "close" { ui.showPluginProposals = false; return }
                try resolvePluginProposal(proposal.id, apply: option == "apply")
                if plugins.proposals.isEmpty { ui.showPluginProposals = false }
            })
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
            guard let answered = center.current else { throw RPCFailure(-32003, "No dialog is open", category: .notAvailableNow) }
            do {
                try center.respond(option: option, path: path, dialog: arguments.optionalString("dialog"))
            } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
            DebugLog.write("ui", "dialog \(answered.name) answered \(option ?? path?.path ?? "")")
            return .object(["answered": answered.json])
        }
    }

    /// `ui.action open DIALOG`.
    func openDialogFromAutomation(_ dialog: String) throws -> JSONValue {
        if let open = ModalCenter.shared.current {
            throw RPCFailure(-32003, "Close the open dialog \(open.name) first", category: .busyDialog)
        }
        guard CommandCatalog.dialogs.contains(dialog) else {
            throw RPCFailure(-32602, "Unknown dialog \(dialog); use " + CommandCatalog.dialogs.joined(separator: ", "))
        }
        try openDialog(dialog)
        return .bool(true)
    }

    /// The Export button's popover while an export runs; Cancel Export stops it.
    private func exportProgressSheet() -> ModalSheet? {
        guard ui.showExportProgress else { return nil }
        return ModalSheet(
            name: "export-progress", title: "Export progress",
            options: [ModalOption("cancel-export", String(localized: "Cancel Export")), Self.close]
        ) { [weak self] option in
            guard let self else { return }
            if option == "cancel-export" { exports.cancelActive() }
            ui.showExportProgress = false
        }
    }

    /// Sheets that only make sense in some states: (available, reason when not, flag).
    private static var conditionalDialogs:
        [String: (available: (ProjectDocument) -> Bool, reason: String, flag: ReferenceWritableKeyPath<EditorUIState, Bool>)]
    {
        [
            "export": ({ $0.project.duration > 0 }, "The timeline is empty", \.showExport),
            "export-report": ({ $0.exports.report != nil }, "No export report yet", \.showExportReport),
            "export-progress": ({ $0.exports.isRunning }, "No export is running", \.showExportProgress),
            "agent-changes": ({ $0.agentChange != nil }, "No agent change to show", \.showAgentChanges),
            "external-changes": ({ $0.conflict }, "The project file has no conflicting change", \.showExternalChanges),
            "plugin-proposals": ({ !$0.plugins.proposals.isEmpty }, "No plugin edits to review", \.showPluginProposals),
        ]
    }

    func openDialog(_ name: String) throws {
        if name == "plugins" { plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent()) }
        if let flag = EditorUIState.toggledDialogs[name] {
            ui[keyPath: flag] = true
        } else if let dialog = Self.conditionalDialogs[name] {
            guard dialog.available(self) else { throw RPCFailure(-32602, dialog.reason) }
            ui[keyPath: dialog.flag] = true
        } else if name == "new-project" {
            newProject()
        } else if name == "add-plugin" {
            guard PluginChannel.current.allowsUserPlugins else { throw RPCFailure(-32602, PluginManagerModel.channelRefusal) }
            plugins.refresh(projectRoot: fileURL?.deletingLastPathComponent())
            ui.showPlugins = true
            plugins.addPlugin()
        } else if name == "knowledge" {
            agents.openKnowledge()
        } else if name == "library-search" || name == "library-generate" {
            // The open library panel's Search… or Generate… (#81).
            let capability = name == "library-search" ? PluginAPI.librarySearch : PluginAPI.libraryGenerate
            let kinds = LibraryKind.kinds(inPanel: ui.libraryTab.panelName)
            guard !libraryProviders(capability, kinds: kinds).isEmpty else {
                throw RPCFailure(-32602, "No plugin provides \(capability) for the \(ui.libraryTab.panelName) panel")
            }
            beginLibrarySearch(capability, kinds: kinds)
        } else {
            throw RPCFailure(-32602, "Unknown dialog \(name)")
        }
        DebugLog.write("ui", "dialog \(name) opened")
    }
}
