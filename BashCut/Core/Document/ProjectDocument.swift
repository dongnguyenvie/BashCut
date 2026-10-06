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
    /// The primary selected item: the one last clicked, which single-item actions and the Inspector use. Setting it
    /// selects that item alone; `select(_:primary:)` selects several.
    var selectedID: String? {
        didSet {
            guard !settingSelection else { return }
            let previous = selectedIDs
            selectedIDs = selectedID.map { [$0] } ?? []
            if selectedID != oldValue || selectedIDs != previous { selectionDidChange() }
        }
    }
    /// Every selected item, in the order they were selected; contains `selectedID`. Set it through `select(_:primary:)`.
    var selectedIDs: [String] = []
    @ObservationIgnored var settingSelection = false
    /// Clips copied or cut from the timeline, pasted at the playhead.
    @ObservationIgnored var clipboard: TimelineClipboard?
    var selectedTrackID: String? {
        didSet { if selectedTrackID != oldValue { selectionDidChange() } }
    }
    var message = ""
    /// Bumped when library items are saved or removed, so the library panels read them again.
    var libraryRevision = 0
    var busy = false
    var dirty = false
    var creatingProject = false
    var privilegedApproval: PrivilegedApprovalPrompt?
    /// An agent edit outside its attached scope, waiting for the user (#356).
    var scopeHold: AgentScopeHold?
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
    let appUpdate = AppUpdateModel.shared
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

    /// Close Project (⇧⌘W): saves unsaved changes, like the autosave would, then shows the Welcome screen. A failed
    /// save (such as a disk conflict) keeps the project open.
    func closeProject() {
        guard fileURL != nil, !busy, !saving else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                if dirty { try await saveNow() }
                closeToWelcome()
            } catch is StorageError {
                message = String(localized: "The project changed on disk; resolve it before closing")
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// The project is saved or its changes are dropped: forget it and show the Welcome screen.
    func closeToWelcome() {
        guard let closed = fileURL else { return }
        DebugLog.write("project", "closed \(closed.path)")
        reset(Project(name: "Untitled"), url: nil)
        message = String(localized: "Project closed")
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
        let movedCaches = ProjectCache.prepare(projectRoot: url.deletingLastPathComponent())
        if !movedCaches.isEmpty {
            DebugLog.write("project", "moved caches into .bashcut/cache: \(movedCaches.joined(separator: ", "))")
        }
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

    /// Shows `project` from `url`, or the Welcome screen with no project when `url` is nil (Close Project).
    func reset(_ project: Project, url: URL?) {
        // Drop deliveries still waiting for the old project, then tell plugins it closed.
        pluginHooks.reset()
        if let previous = fileURL {
            emitPluginEvent(.projectClosed, ["path": .string(previous.path), "name": .string(self.project.name)])
        }
        plugins.proposals.removeAll()
        plugins.pendingAction = nil
        if privilegedApproval != nil { resolvePrivilegedApproval(false) }
        resolveScopeHold(.reject)
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
        if let url {
            exports.restoreReport(projectRoot: url.deletingLastPathComponent())
            settings.rememberRecentProject(url)
        }
        selectedID = nil
        selectedTrackID = nil
        timelineGestureActive = false
        dirty = false
        message = ""
        startExternalFileMonitor()
        agents.projectChanged()
        chatAgents.projectChanged()
        registry.projectSwitched(to: url == nil ? "no project" : project.name)
        agents.keepSessions(after: liveBookmarks)
        plugins.refresh(projectRoot: url?.deletingLastPathComponent())
        if settings.checkPluginUpdatesDaily { Task { await plugins.checkForUpdatesIfDue() } }
        if settings.checkAppUpdatesDaily { checkAppUpdateIfDue() }
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
        if selectedIDs.count > 1 {
            try commitSelection(
                SelectionEdits.delete(selectedIDs, ripple: ripple, in: project),
                label: ripple ? "Ripple delete clips" : "Lift clips", author: author)
        } else {
            try commit(.delete(item: selectedID, ripple: ripple), label: ripple ? "Ripple delete" : "Lift clip", author: author)
        }
        self.selectedID = nil
    }
    func rebuild(coalescing: Bool = false) {
        let root = fileURL?.deletingLastPathComponent()
        if let root { waveforms.update(media: project.media, root: root) }
        preview.rebuild(project, root: root, workspace: settings.workspace, coalescing: coalescing)
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
        try commitEdit(
            operation, label: label, author: author, baseRevision: baseRevision, coalescingKey: coalescingKey
        ).revision
    }

    /// `commit`, also reporting whether the edit changed anything. An edit that changes nothing keeps the
    /// revision, adds no undo step, leaves the agent diff alone and emits no plugin event.
    func commitEdit(
        _ operation: EditOperation, label: String, author: Author = .user, baseRevision: Int? = nil,
        coalescingKey: String? = nil
    ) throws -> (revision: Int, changed: Bool) {
        let scope = try checkAgentScope(
            operation, label: label, author: author, baseRevision: baseRevision, coalescingKey: coalescingKey)
        let before = project
        let (operation, firstClipCanvas) = withFirstClipCanvas(operation, label: label, author: author)
        let changed: Bool
        do {
            try ensureEditable(author: author)
            changed = try history.apply(
                operation, label: label, author: author, baseRevision: baseRevision, coalescingKey: coalescingKey)
        } catch {
            DebugLog.write(
                "edit", "REJECTED edit by \(author) base=\(baseRevision.map(String.init) ?? "-") "
                    + "rev=\(before.revision) op=\(Self.describe(operation))")
            throw error
        }
        guard changed else {
            DebugLog.write("edit", "no-op edit by \(author) rev \(before.revision) op=\(Self.describe(operation))")
            return (project.revision, false)
        }
        didCommit(from: before, author: author, label: label, coalescing: coalescingKey != nil)
        recordScopeEdit(scope, before: before)
        if let firstClipCanvas {
            let name = switch firstClipCanvas {
            case .portrait: String(localized: "Portrait · 9:16")
            case .landscape: String(localized: "Landscape · 16:9")
            case .square: String(localized: "Square · 1:1")
            }
            message = String(format: String(localized: "Canvas set to %@ to match the first clip"), name)
        }
        emitPluginEvent(.editCommitted, editEventPayload(label: label, author: author, before: before))
        DebugLog.write(
            "edit", "edit by \(author) rev \(before.revision)→\(project.revision) op=\(Self.describe(operation))"
                + (before.tracks.map(\.id) == project.tracks.map(\.id) ? "" : " layers: \(layoutSummary())"))
        return (project.revision, true)
    }

    /// The first picture clip on an empty timeline sets the canvas shape, in the same undo step as the clip.
    private func withFirstClipCanvas(
        _ operation: EditOperation, label: String, author: Author
    ) -> (EditOperation, ProjectSetup.Canvas?) {
        guard author != .external, project.canvasFromFirstClip, !project.hasPictureClip,
            let next = try? project.applying(operation).project,
            let format = project.formatForFirstClip(in: next)
        else { return (operation, nil) }
        DebugLog.write("edit", "first clip sets the canvas to \(format.canvas.rawValue) \(format.width)x\(format.height)")
        let ops: [EditOperation] = [operation, .setFormat(width: format.width, height: format.height)]
        return (.group(label: label, author: author, ops: ops), format.canvas)
    }

    func dryRunEdit(_ operation: EditOperation, author: Author, baseRevision: Int) throws -> JSONValue {
        try ensureEditable(author: author)
        return try TimelineDryRun.evaluate(operation, on: project, baseRevision: baseRevision)
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

    private func didCommit(from before: Project, author: Author, label: String, coalescing: Bool = false) {
        if author.isAgent {
            markAgentChanges(from: before, author: author, label: label)
            message = author.rawValue.capitalized + ": " + label
        } else {
            clearAgentChange()
        }
        dirty = true
        rebuild(coalescing: coalescing)
    }
}

/// Thrown when an agent edit arrives while the user is mid-gesture or a long operation runs.
struct AutomationBusy: LocalizedError, RPCFailureProviding {
    var errorDescription: String? { rpcFailure.message }
    var rpcFailure: RPCFailure { RPCFailure(-32003, "The editor is busy or has a file conflict; retry later") }
}

extension Author {
    /// Agent-authored edits get the ◆ diff markers and the Undo toast.
    var isAgent: Bool { [.claude, .codex, .model, .agent, .plugin].contains(self) }
}
