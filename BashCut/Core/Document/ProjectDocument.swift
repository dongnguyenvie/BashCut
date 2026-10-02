import AVFoundation
import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutImport
import BashCutProject
import BashCutStorage
import OSLog
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ProjectDocument {
    /// Mutated only through `commit`, `commitUndo`/`commitRedo` and `replaceHistory` below.
    private(set) var history = ProjectHistory(project: Project(name: "Untitled"))
    var selectedID: String?
    var selectedTrackID: String?
    var message = ""
    var busy = false
    var dirty = false
    var creatingProject = false
    var exportReport: ExportReport?
    var privilegedApproval: PrivilegedApprovalPrompt?
    var fileURL: URL?
    let sourceViewer = SourceViewerModel()
    let waveforms = WaveformModel()
    let storage = ProjectStorage()
    var diskData: Data?
    var externalData: Data?
    var externalProject: Project?
    var conflict = false
    var legacyImportReport: LegacyEDLImportReport?
    var saving = false
    var fileCheckInProgress = false
    @ObservationIgnored var fileMonitor: ProjectFileMonitor?
    var lastAutosaveRevision = -1
    var sessionID = UUID()
    let automationServer = UnixRPCServer()
    let registry: CommandRegistry
    var agentChangedIDs = Set<String>()
    var agentChange: AgentChangeRecord?
    let doctor = DoctorModel()
    var timelineGestureActive = false
    var recentProjectURLs: [URL]
    /// Zoom, toggles, panels and open sheets.
    let ui = EditorUIState()
    @ObservationIgnored lazy var agents = AgentDockModel(document: self)
    @ObservationIgnored lazy var plugins = PluginManagerModel()
    @ObservationIgnored var privilegedAction: (@MainActor () throws -> Void)?
    let engine: any RenderEngine
    /// Program and comparison players, the playhead and the composition they play.
    let preview: PreviewController
    /// Capability calls and exports, listed by `jobs.status` and cancelled by `jobs.cancel`.
    let jobs = JobCenter()
    @ObservationIgnored lazy var exports = ExportQueue(jobs: jobs) { [unowned self] in
        ExportPipeline(engine: engine, loudness: plugins.service)
    }
    /// Token of the external-agent file; it outlives project switches, unlike in-app terminal tokens.
    @ObservationIgnored var externalAgentToken: String?

    init(engine: any RenderEngine = AVFoundationRenderEngine()) {
        self.engine = engine
        preview = PreviewController(engine: engine)
        recentProjectURLs = UserDefaults.standard.stringArray(forKey: "recentProjectPaths")?
            .map { URL(fileURLWithPath: $0) } ?? []
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/BashCut/audit.jsonl")
        let audit = AuditStore(url: url)
        registry = CommandRegistry { event in
            Task {
                do { try await audit.append(event) } catch {
                    Logger(subsystem: "app.bashcut", category: "automation").error("Audit write failed")
                }
            }
        }
        preview.onMessage = { [weak self] in self?.message = $0 }
    }

    var project: Project { history.project }
    var playhead: Int { preview.playhead }
    var exporting: Bool { exports.isRunning }
    var exportProgress: Double { exports.progress }
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
        panel.directoryURL = recentProjectURLs.first?.deletingLastPathComponent()
        guard let url = ModalCenter.shared.open(panel, name: "open-project")?.first else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard !busy, !saving, confirmDiscard() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            forgetRecentProject(url)
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
        diskData = loaded.diskData
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
        fileMonitor?.cancel()
        fileMonitor = nil
        if privilegedApproval != nil { resolvePrivilegedApproval(false) }
        agents.closeAll()
        sourceViewer.reset()
        waveforms.reset()
        agentChangedIDs.removeAll()
        agentChange = nil
        sessionID = UUID()
        diskData = nil
        externalData = nil
        externalProject = nil
        conflict = false
        legacyImportReport = nil
        lastAutosaveRevision = -1
        exports.cancelAll()
        jobs.cancelAll()
        exportReport = nil
        ui.closeProjectSheets()
        privilegedApproval = nil
        privilegedAction = nil
        replaceHistory(ProjectHistory(project: project))
        preview.reset(project)
        fileURL = url
        restoreExportReport()
        rememberRecentProject(url)
        selectedID = nil
        selectedTrackID = nil
        timelineGestureActive = false
        dirty = false
        message = ""
        startExternalFileMonitor()
        agents.projectChanged()
    }

    func clearRecentProjects() {
        recentProjectURLs.removeAll()
        UserDefaults.standard.removeObject(forKey: "recentProjectPaths")
    }

    private func rememberRecentProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentProjectURLs.removeAll { $0.standardizedFileURL == normalized }
        recentProjectURLs.insert(normalized, at: 0)
        if recentProjectURLs.count > 8 { recentProjectURLs.removeLast(recentProjectURLs.count - 8) }
        UserDefaults.standard.set(recentProjectURLs.map(\.path), forKey: "recentProjectPaths")
    }

    private func forgetRecentProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentProjectURLs.removeAll { $0.standardizedFileURL == normalized }
        UserDefaults.standard.set(recentProjectURLs.map(\.path), forKey: "recentProjectPaths")
    }

    func addCaption() {
        var item = Item(at: playhead, duration: max(1, min(90, project.duration - playhead)))
        item["text"] = .string("Món ngon ở Buôn Ma Thuột")
        item["style"] = .string("bold-outline")
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
        preview.rebuild(project, root: root, workspace: agents.workspace)
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
        DebugLog.write(
            "edit", "\"\(label)\" by \(author) rev \(before.revision)→\(project.revision) op=\(Self.describe(operation))"
                + (before.tracks.map(\.id) == project.tracks.map(\.id) ? "" : " layers: \(layoutSummary())"))
        return project.revision
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
    var isAgent: Bool { [.claude, .codex, .model, .agent].contains(self) }
}
