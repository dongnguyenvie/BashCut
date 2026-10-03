import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutImport
import BashCutProject
import BashCutStorage
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ProjectDocument {
    /// Mutated only through `commit`, `commitUndo`/`commitRedo` and `replaceHistory` below.
    private(set) var history = ProjectHistory(project: Project(name: "Untitled"))
    var selectedID: String? {
        didSet { if selectedID != oldValue { selectionDidChange() } }
    }
    var selectedTrackID: String? {
        didSet { if selectedTrackID != oldValue { selectionDidChange() } }
    }
    var message = ""
    var busy = false
    var dirty = false
    var creatingProject = false
    var privilegedApproval: PrivilegedApprovalPrompt?
    var fileURL: URL?
    let sourceViewer = SourceViewerModel()
    let waveforms = WaveformModel()
    /// Saves, autosaves and the disk watch for the open file.
    let fileSync = FileSyncController()
    /// Report of the timeline import that created the open project.
    var importReport: TimelineImport?
    var sessionID = UUID()
    /// Socket server, command registry and the external-agent token file.
    let automation: AutomationController
    var agentChangedIDs = Set<String>()
    var agentChange: AgentChangeRecord?
    let doctor = DoctorModel()
    /// A timeline drag is in progress; only guards autosave and agent edits, so views do not observe it.
    @ObservationIgnored var timelineGestureActive = false
    /// Preferences and recent projects.
    let settings: SettingsModel
    /// Zoom, toggles, panels and open sheets.
    let ui = EditorUIState()
    @ObservationIgnored lazy var agents = AgentDockModel(document: self)
    @ObservationIgnored lazy var chatAgents = ChatAgents(document: self)
    @ObservationIgnored lazy var plugins = PluginManagerModel()
    @ObservationIgnored lazy var pluginHooks = PluginHookDispatcher(document: self)
    /// The plugin whose proposal is being committed, so its own hooks do not hear about it.
    @ObservationIgnored var pluginEditSource: String?
    @ObservationIgnored var privilegedAction: (@MainActor () throws -> Void)?
    let engine: any RenderEngine
    /// Program and comparison players, the playhead and the composition they play.
    let preview: PreviewController
    /// Capability calls and exports, listed by `jobs.status` and cancelled by `jobs.cancel`.
    let jobs = JobCenter()
    @ObservationIgnored lazy var exports = ExportController(jobs: jobs) { [unowned self] in
        ExportPipeline(engine: engine, loudness: plugins.service)
    }
    /// Preview proxies for heavy footage, made one at a time; the preview rebuilds as each one lands.
    @ObservationIgnored lazy var proxies: ProxyQueue = {
        let queue = ProxyQueue(jobs: jobs)
        queue.onFinished = { [weak self] _ in self?.rebuild() }
        return queue
    }()

    /// App-wide services come from `services`; per-project controllers are created here.
    init(services: AppServices) {
        engine = services.engine
        settings = services.settings
        automation = services.automation
        preview = PreviewController(engine: services.engine)
        preview.onMessage = { [weak self] in self?.message = $0 }
        preview.onPlaybackStopped = { [weak self] frame in
            self?.emitPluginEvent(.playbackStopped, ["playhead": .integer(frame)])
        }
        jobs.onFinished = { [weak self] job in
            guard job.method != "plugins.run" || job.state != .completed else { return }
            self?.emitPluginEvent(.jobFinished, job.json.object)
        }
    }

    var project: Project { history.project }
    var registry: CommandRegistry { automation.registry }
    var playhead: Int { preview.playhead }
    var selected: Item? { project.tracks.flatMap(\.items).first { $0.id == selectedID } }
    var selectedItemTrack: Track? {
        guard let selectedID else { return nil }
        return project.tracks.first { $0.items.contains(where: { $0.id == selectedID }) }
    }

    func confirmDiscard(removeRecovery: Bool = true) -> Bool {
        guard dirty else { return true }
        let choice = ModalCenter.shared.alert(
            "discard-changes", title: String(localized: "Discard unsaved changes?"),
            buttons: [ModalOption("cancel", String(localized: "Cancel")), ModalOption("discard", String(localized: "Discard"))])
        guard choice == "discard" else { return false }
        if removeRecovery, let fileURL {
            Task {
                do { try await storage.discardRecovery(at: fileURL) } catch {
                    message = error.localizedDescription
                }
            }
        }
        return true
    }

    func newProject() {
        guard !busy, !saving else { return }
        ui.showNewProject = true
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = settings.recentProjects.first?.deletingLastPathComponent()
        guard let url = ModalCenter.shared.open(panel, name: "open-project")?.first else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard !busy, !saving, confirmDiscard() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            settings.forgetRecentProject(url)
            message = String(localized: "The project file is no longer available")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await loadProject(at: url, offerRecovery: true)
            } catch {
                DebugLog.write("project", "open FAILED \(url.path): \(error.localizedDescription)")
                message = error.localizedDescription
            }
        }
    }

    /// Loads and shows a project. With `offerRecovery`, asks whether to restore autosaved edits; automation
    /// keeps the saved project and leaves the recovery file for the next interactive open.
    func loadProject(at url: URL, offerRecovery: Bool) async throws {
        let loaded = try await storage.load(url)
        reset(loaded.history.project, url: url)
        replaceHistory(loaded.history)
        fileSync.accept(loaded.diskData)
        logOpened(url, data: loaded.diskData)
        message = loaded.warning ?? ""
        if let warning = loaded.warning { DebugLog.write("project", "warning: \(warning)") }
        if offerRecovery, let recovery = loaded.recovery {
            let choice = ModalCenter.shared.alert(
                "recover-edits", title: String(localized: "Recover unsaved edits?"),
                buttons: [ModalOption("recover", String(localized: "Recover")),
                          ModalOption("use-saved", String(localized: "Use saved project"))])
            if choice == "recover" {
                replaceHistory(recovery)
                dirty = true
            } else {
                try await storage.discardRecovery(at: url)
            }
        }
        restoreLatestAgentChangeFromHistory()
        relinkOlderMediaPaths(projectRoot: url.deletingLastPathComponent())
        rebuild()
        emitPluginEvent(.projectOpened, [
            "path": .string(url.path), "name": .string(project.name), "rev": .integer(project.revision),
        ])
    }

    /// Projects saved before footage paths went through the `footage` link store `../../…` paths;
    /// rewrite them as one undoable edit so the project survives a move.
    private func relinkOlderMediaPaths(projectRoot: URL) {
        guard let relinked = MediaPathResolver.relinkingMedia(in: project, projectRoot: projectRoot) else { return }
        do {
            try commit(.restore(relinked), label: "Relink media paths", author: .user)
            message = String(localized: "Media paths now go through the footage link; save to keep them")
            DebugLog.write("project", "relinked media paths through project folder links")
        } catch {
            DebugLog.write("project", "relink skipped: \(error.localizedDescription)")
        }
    }

    func reset(_ project: Project, url: URL) {
        // Drop deliveries still waiting for the old project, then tell plugins it closed.
        pluginHooks.reset()
        if let previous = fileURL {
            emitPluginEvent(.projectClosed, ["path": .string(previous.path), "name": .string(self.project.name)])
        }
        plugins.proposals.removeAll()
        plugins.pendingAction = nil
        if privilegedApproval != nil { resolvePrivilegedApproval(false) }
        // Terminals stay open; pending session lookups end with the old project.
        let liveBookmarks = agents.liveBookmarks()
        agents.resetProjectState()
        sourceViewer.reset()
        waveforms.reset()
        agentChangedIDs.removeAll()
        agentChange = nil
        sessionID = UUID()
        fileSync.reset()
        importReport = nil
        exports.reset()
        proxies.cancelAll()
        jobs.cancelAll()
        ui.closeProjectSheets()
        privilegedApproval = nil
        privilegedAction = nil
        replaceHistory(ProjectHistory(project: project))
        preview.reset(project)
        fileURL = url
        exports.restoreReport(projectRoot: url.deletingLastPathComponent())
        settings.rememberRecentProject(url)
        selectedID = nil
        selectedTrackID = nil
        timelineGestureActive = false
        dirty = false
        message = ""
        startExternalFileMonitor()
        agents.projectChanged()
        chatAgents.projectChanged()
        registry.projectSwitched(to: project.name)
        agents.keepSessions(after: liveBookmarks)
        plugins.refresh(projectRoot: url.deletingLastPathComponent())
        if settings.checkPluginUpdatesDaily { Task { await plugins.checkForUpdatesIfDue() } }
    }

    func addCaption() {
        var item = Item(at: playhead, duration: max(1, min(90, project.duration - playhead)))
        item["text"] = .string("Món ngon ở Buôn Ma Thuột")
        item["textPreset"] = .string("bold-outline")
        do {
            try commit(.insert(track: project.requireTrack(role: TrackRole.captions).id, item: item), label: "Add caption")
        } catch { message = error.localizedDescription }
        selectedID = item.id
    }
    func split(author: Author = .user) throws {
        guard let selectedID else { throw ProjectError.invalid("Select a clip to split") }
        try commit(.split(item: selectedID, atFrame: playhead, newID: UUID().uuidString), label: "Split", author: author)
    }
    func delete(ripple: Bool = true, author: Author = .user) throws {
        guard let selectedID else { throw ProjectError.invalid("Select a clip to delete") }
        try commit(.delete(item: selectedID, ripple: ripple), label: ripple ? "Ripple delete" : "Lift clip", author: author)
        self.selectedID = nil
    }
    func rebuild() {
        let root = fileURL?.deletingLastPathComponent()
        if let root { waveforms.update(media: project.media, root: root) }
        preview.rebuild(project, root: root, workspace: settings.workspace)
    }
}

// MARK: - Edit choke point

extension ProjectDocument {
    /// The only way an edit enters history. It enforces conflict, busy and revision rules, records or
    /// clears the agent diff, marks the document dirty and rebuilds the preview.
    @discardableResult
    func commit(
        _ operation: EditOperation, label: String, author: Author = .user, baseRevision: Int? = nil,
        coalescingKey: String? = nil
    ) throws -> Int {
        let before = project
        do {
            try ensureEditable(author: author)
            try history.apply(
                operation, label: label, author: author, baseRevision: baseRevision, coalescingKey: coalescingKey)
        } catch {
            DebugLog.write(
                "edit", "REJECTED \"\(label)\" by \(author) base=\(baseRevision.map(String.init) ?? "-") "
                    + "rev=\(before.revision): \(error.localizedDescription) op=\(Self.describe(operation))")
            throw error
        }
        didCommit(from: before, author: author, label: label)
        emitPluginEvent(.editCommitted, editEventPayload(label: label, author: author, before: before))
        DebugLog.write(
            "edit", "\"\(label)\" by \(author) rev \(before.revision)→\(project.revision) op=\(Self.describe(operation))"
                + (before.tracks.map(\.id) == project.tracks.map(\.id) ? "" : " layers: \(layoutSummary())"))
        return project.revision
    }

    func previewEdit(_ operation: EditOperation, author: Author, baseRevision: Int) throws -> JSONValue {
        try ensureEditable(author: author)
        return try TimelineEditPreview.evaluate(operation, on: project, baseRevision: baseRevision)
    }

    @discardableResult
    func commitUndo(author: Author = .user, baseRevision: Int? = nil) throws -> Int {
        try commitHistoryStep(undo: true, author: author, baseRevision: baseRevision)
    }

    @discardableResult
    func commitRedo(author: Author = .user, baseRevision: Int? = nil) throws -> Int {
        try commitHistoryStep(undo: false, author: author, baseRevision: baseRevision)
    }

    /// Replaces history wholesale when a project is opened, recovered or imported.
    func replaceHistory(_ replacement: ProjectHistory) {
        history = replacement
        clearAgentChange()
    }

    /// UI convenience: reports failures in the status bar instead of throwing.
    func apply(_ operation: EditOperation, label: String) {
        // Failures are logged by `commit`.
        do { try commit(operation, label: label) } catch { message = error.localizedDescription }
    }

    func undo() { run(.undo) }

    func redo() { run(.redo) }

    private func commitHistoryStep(undo: Bool, author: Author, baseRevision: Int?) throws -> Int {
        try ensureEditable(author: author)
        if let baseRevision, baseRevision != project.revision {
            throw ProjectError.staleRevision(expected: baseRevision, actual: project.revision)
        }
        let before = project
        if undo { try history.undo() } else { try history.redo() }
        didCommit(from: before, author: author, label: undo ? "Undo" : "Redo")
        emitPluginEvent(
            undo ? .editUndone : .editRedone, editEventPayload(label: undo ? "Undo" : "Redo", author: author, before: before))
        DebugLog.write("edit", "\(undo ? "undo" : "redo") by \(author) rev \(before.revision)→\(project.revision)")
        return project.revision
    }

    private func ensureEditable(author: Author) throws {
        // External reloads resolve conflicts themselves; everything else waits for the user.
        guard author == .external || !conflict else {
            throw ProjectError.invalid(String(localized: "Resolve the file conflict before editing."))
        }
        if author.isAgent, busy || timelineGestureActive {
            throw AutomationBusy()
        }
    }

    private func didCommit(from before: Project, author: Author, label: String) {
        if author.isAgent {
            markAgentChanges(from: before, author: author, label: label)
            message = author.rawValue.capitalized + ": " + label
        } else {
            clearAgentChange()
        }
        dirty = true
        rebuild()
    }
}

/// Thrown when an agent edit arrives while the user is mid-gesture or a long operation runs.
struct AutomationBusy: LocalizedError {
    var errorDescription: String? { "The editor is busy or has a file conflict; retry later" }
}

extension Author {
    /// Agent-authored edits get the ◆ diff markers and the Undo toast.
    var isAgent: Bool { [.claude, .codex, .model, .agent, .plugin].contains(self) }
}
