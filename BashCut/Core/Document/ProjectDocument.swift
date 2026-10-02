import AVFoundation
import AppKit
import BashCutAutomation
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
    var playhead = 0
    var message = ""
    var busy = false
    var dirty = false
    var showNewProject = false
    var creatingProject = false
    var showExport = false
    var exporting = false
    var exportProgress = 0.0
    var exportReport: ExportReport?
    var showExportReport = false
    var privilegedApproval: PrivilegedApprovalPrompt?
    var fileURL: URL?
    let player = AVPlayer()
    let comparisonPlayer = AVPlayer()
    let sourceViewer = SourceViewerModel()
    let waveforms = WaveformModel()
    let storage = ProjectStorage()
    var diskData: Data?
    var externalData: Data?
    var externalProject: Project?
    var conflict = false
    var showExternalChanges = false
    var legacyImportReport: LegacyEDLImportReport?
    var showLegacyImportReport = false
    var saving = false
    var fileCheckInProgress = false
    @ObservationIgnored var fileMonitor: ProjectFileMonitor?
    var lastAutosaveRevision = -1
    var sessionID = UUID()
    let automationServer = UnixRPCServer()
    let registry: CommandRegistry
    var agentChangedIDs = Set<String>()
    var agentChange: AgentChangeRecord?
    var showAgentChanges = false
    var showAgentDock = true
    var libraryTab: LibraryTab = .media
    var timelineScale = 50.0
    var snapping = true
    var timelineGestureActive = false
    var showSafeArea = false
    var showColorComparison = false
    var recentProjectURLs: [URL]
    @ObservationIgnored lazy var agents = AgentDockModel(document: self)
    @ObservationIgnored lazy var plugins = PluginManagerModel()
    @ObservationIgnored var privilegedAction: (@MainActor () throws -> Void)?
    let engine: any RenderEngine
    @ObservationIgnored var snapshot: CompositionSnapshot?
    private var comparisonSnapshot: CompositionSnapshot?
    private var rebuildTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?
    var capabilityJobs: [CapabilityJob] = []
    @ObservationIgnored var capabilityTasks: [String: Task<Void, Never>] = [:]
    /// Token of the external-agent file; it outlives project switches, unlike in-app terminal tokens.
    @ObservationIgnored var externalAgentToken: String?

    init(engine: any RenderEngine = AVFoundationRenderEngine()) {
        self.engine = engine
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
        comparisonPlayer.isMuted = true
    }

    var project: Project { history.project }
    var selected: Item? { project.tracks.flatMap(\.items).first { $0.id == selectedID } }
    var selectedItemTrack: Track? {
        guard let selectedID else { return nil }
        return project.tracks.first { $0.items.contains(where: { $0.id == selectedID }) }
    }

    func confirmDiscard(removeRecovery: Bool = true) -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Discard unsaved changes?")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Discard"))
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
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
        showNewProject = true
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = recentProjectURLs.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
            let alert = NSAlert()
            alert.messageText = String(localized: "Recover unsaved edits?")
            alert.addButton(withTitle: String(localized: "Recover"))
            alert.addButton(withTitle: String(localized: "Use saved project"))
            if alert.runModal() == .alertFirstButtonReturn {
                replaceHistory(recovery)
                dirty = true
            } else {
                try await storage.discardRecovery(at: url)
            }
        }
        restoreLatestAgentChangeFromHistory()
        rebuild()
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
        showAgentChanges = false
        sessionID = UUID()
        diskData = nil
        externalData = nil
        externalProject = nil
        conflict = false
        showExternalChanges = false
        legacyImportReport = nil
        showLegacyImportReport = false
        lastAutosaveRevision = -1
        rebuildTask?.cancel()
        exportTask?.cancel()
        cancelCapabilityJobs()
        exporting = false
        exportProgress = 0
        exportReport = nil
        showExportReport = false
        privilegedApproval = nil
        privilegedAction = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        snapshot = nil
        comparisonPlayer.replaceCurrentItem(with: nil)
        comparisonSnapshot = nil
        showColorComparison = false
        comparisonSnapshot = nil
        replaceHistory(ProjectHistory(project: project))
        fileURL = url
        restoreExportReport()
        rememberRecentProject(url)
        selectedID = nil
        selectedTrackID = nil
        timelineGestureActive = false
        playhead = 0
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
    func split() {
        guard let selectedID else { return }
        apply(.split(item: selectedID, atFrame: playhead, newID: UUID().uuidString), label: "Split")
    }
    func delete(ripple: Bool = true) {
        guard let selectedID else { return }
        apply(.delete(item: selectedID, ripple: ripple), label: ripple ? "Ripple delete" : "Lift clip")
        self.selectedID = nil
    }
    func rebuild() {
        if let root = fileURL?.deletingLastPathComponent() { waveforms.update(media: project.media, root: root) }
        rebuildTask?.cancel()
        snapshot = nil
        comparisonSnapshot = nil
        player.pause()
        comparisonPlayer.pause()
        player.replaceCurrentItem(with: nil)
        comparisonPlayer.replaceCurrentItem(with: nil)
        guard let root = fileURL?.deletingLastPathComponent(), project.duration > 0 else { return }
        let value = project
        let compare = showColorComparison
        rebuildTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(50))
                let built = try await engine.build(value, root: root, workspace: agents.workspace)
                let comparisonBuilt = compare
                    ? try await engine.build(
                        value.withoutColorEffects(), root: root, workspace: agents.workspace)
                    : nil
                try Task.checkCancellation()
                guard value.revision == project.revision, compare == showColorComparison else { return }
                snapshot = built
                let item = AVPlayerItem(asset: built.composition)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                player.replaceCurrentItem(with: item)
                var comparisonItem: AVPlayerItem?
                if let comparisonBuilt {
                    comparisonSnapshot = comparisonBuilt
                    let original = AVPlayerItem(asset: comparisonBuilt.composition)
                    original.videoComposition = comparisonBuilt.videoComposition
                    original.audioMix = comparisonBuilt.audioMix
                    comparisonPlayer.replaceCurrentItem(with: original)
                    comparisonItem = original
                }
                try await waitUntilReady(item, message: "Preview could not become ready")
                if let comparisonItem {
                    try await waitUntilReady(
                        comparisonItem, message: "Comparison preview could not become ready")
                }
                seek(playhead)
                message = ""
            } catch is CancellationError {} catch { message = error.localizedDescription }
        }
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

    func undo() {
        do { try commitUndo() } catch { message = error.localizedDescription }
    }

    func redo() {
        do { try commitRedo() } catch { message = error.localizedDescription }
    }

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
