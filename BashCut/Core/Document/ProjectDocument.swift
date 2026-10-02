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
    var history = ProjectHistory(project: Project(name: "Untitled"))
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

    func apply(_ operation: EditOperation, label: String) {
        guard !conflict else {
            message = String(localized: "Resolve the file conflict before editing.")
            return
        }
        do {
            try history.apply(operation, label: label)
            clearAgentChange()
            dirty = true
            rebuild()
        } catch { message = error.localizedDescription }
    }

    func undo() {
        do {
            try history.undo()
            clearAgentChange()
            dirty = true
            rebuild()
        } catch { message = error.localizedDescription }
    }
    func redo() {
        do {
            try history.redo()
            clearAgentChange()
            dirty = true
            rebuild()
        } catch { message = error.localizedDescription }
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
                let loaded = try await storage.load(url)
                reset(loaded.history.project, url: url)
                history = loaded.history
                diskData = loaded.diskData
                message = loaded.warning ?? ""
                if let recovery = loaded.recovery {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Recover unsaved edits?")
                    alert.addButton(withTitle: String(localized: "Recover"))
                    alert.addButton(withTitle: String(localized: "Use saved project"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        history = recovery
                        dirty = true
                    } else {
                        try await storage.discardRecovery(at: url)
                    }
                }
                restoreLatestAgentChangeFromHistory()
                rebuild()
            } catch { message = error.localizedDescription }
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
        history = ProjectHistory(project: project)
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

    func addTrack(kind: String) {
        let roles = ["video": "overlay", "text": "captions", "audio": "audio"]
        let prefix = ["video": "v", "text": "t", "audio": "a"]
        let count = project.tracks.filter { $0.kind == kind }.count + 1
        var id = "\(prefix[kind] ?? "track")\(count)"
        while project.tracks.contains(where: { $0.id == id }) { id += "-new" }
        var track = Track(id: id, kind: kind, role: roles[kind] ?? kind)
        track.name = String(localized: "New \(kind.capitalized) Layer")
        let index = kind == "audio"
            ? project.tracks.count
            : project.tracks.firstIndex(where: { $0.kind == "audio" }) ?? project.tracks.count
        apply(.addTrack(track: track, atIndex: index), label: "Add \(kind) layer")
        selectedTrackID = id
    }

    func deleteSelectedTrack() {
        guard let id = selectedTrackID else { return }
        apply(.deleteTrack(track: id), label: "Delete layer")
        if !project.tracks.contains(where: { $0.id == id }) { selectedTrackID = nil }
    }

    func moveSelectedTrack(by offset: Int) {
        guard let id = selectedTrackID, let index = project.tracks.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = min(project.tracks.count - 1, max(0, index + offset))
        guard destination != index else { return }
        apply(.moveTrack(track: id, toIndex: destination), label: "Reorder layer")
    }

    func addCaption() {
        var item = Item(at: playhead, duration: max(1, min(90, project.duration - playhead)))
        item["text"] = .string("Món ngon ở Buôn Ma Thuột")
        item["style"] = .string("bold-outline")
        apply(.insert(track: "t1", item: item), label: "Add caption")
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
