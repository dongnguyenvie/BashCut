import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Editor buttons, menu items and shortcuts run through `run(_:)`; `ui.action` runs the same code
/// for agents, and `ui.view` reads or sets the view state (zoom, toggles, timeline scroll).
extension ProjectDocument {
    static let timelineZoomRange: ClosedRange<Double> = 10...140
    private static let zoomStep = 1.25

    /// Whether the action's button is enabled right now.
    func canPerform(_ action: UIAction) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        guard !busy else { return false }
        let hasProject = fileURL != nil
        let source = sourceViewer.visible && sourceViewer.media != nil
        switch action {
        case .undo: return !history.undoEntries.isEmpty
        case .redo: return !history.redoEntries.isEmpty
        case .newProject, .openProject: return !saving
        case .saveProject: return hasProject && !saving && !conflict
        case .importMedia, .refreshWaveforms: return hasProject && !(action == .refreshWaveforms && waveforms.loading)
        case .showExport, .toggleCompare: return project.duration > 0
        case .togglePlayback, .previousFrame, .nextFrame: return project.duration > 0 && !sourceViewer.visible
        case .zoomIn: return timelineScale < Self.timelineZoomRange.upperBound
        case .zoomOut: return timelineScale > Self.timelineZoomRange.lowerBound
        case .split, .delete, .lift: return selected != nil
        case .layerUp, .layerDown, .deleteLayer: return selectedTrackID != nil
        case .sourceTogglePlayback, .sourcePreviousFrame, .sourceNextFrame, .markIn, .markOut, .sourceInsert,
            .sourceOverwrite, .sourceClose:
            return source
        case .showHistory, .showReview, .showPlugins, .showDoctor, .showSettings, .showSections, .toggleAgentDock,
            .askAgent, .toggleSafeArea, .toggleSnap, .addVideoLayer, .addTextLayer, .addAudioLayer:
            return true
        }
    }

    /// Runs an action from a button or shortcut; failures go to the status bar.
    func run(_ action: UIAction) {
        guard canPerform(action) else { return }
        do { try perform(action, author: .user) } catch { message = error.localizedDescription }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func perform(_ action: UIAction, author: Author) throws {
        DebugLog.write("ui", "action \(action.id) by \(author)")
        switch action {
        case .undo: _ = try commitUndo(author: author)
        case .redo: _ = try commitRedo(author: author)
        case .newProject: newProject()
        case .openProject: openProject()
        case .saveProject: save()
        case .importMedia: importMedia()
        case .showHistory, .showReview, .showPlugins, .showDoctor, .showSettings, .showExport, .showSections:
            try openDialog(String(action.id.dropFirst("show.".count)))
        case .toggleAgentDock:
            if agents.isDetached { agents.attach() } else { showAgentDock.toggle() }
        case .askAgent: showAsk = true
        case .togglePlayback: togglePlayback()
        case .previousFrame: seek(playhead - 1)
        case .nextFrame: seek(playhead + 1)
        case .toggleCompare: setColorComparison(!showColorComparison)
        case .toggleSafeArea: showSafeArea.toggle()
        case .toggleSnap: snapping.toggle()
        case .zoomIn: setTimelineZoom(timelineScale * Self.zoomStep)
        case .zoomOut: setTimelineZoom(timelineScale / Self.zoomStep)
        default: try performTimelineAction(action, author: author)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func performTimelineAction(_ action: UIAction, author: Author) throws {
        switch action {
        case .split: try split(author: author)
        case .delete: try delete(ripple: true, author: author)
        case .lift: try delete(ripple: false, author: author)
        case .refreshWaveforms:
            if let root = fileURL?.deletingLastPathComponent() { waveforms.refresh(media: project.media, root: root) }
        case .addVideoLayer: selectedTrackID = try addLayer(kind: "video", author: author).trackID
        case .addTextLayer: selectedTrackID = try addLayer(kind: "text", author: author).trackID
        case .addAudioLayer: selectedTrackID = try addLayer(kind: "audio", author: author).trackID
        case .layerUp: try moveSelectedTrack(by: 1, author: author)
        case .layerDown: try moveSelectedTrack(by: -1, author: author)
        case .deleteLayer: try deleteSelectedTrack(author: author)
        case .sourceTogglePlayback: sourceViewer.togglePlayback()
        case .sourcePreviousFrame: sourceViewer.seek(sourceViewer.frame - 1)
        case .sourceNextFrame: sourceViewer.seek(sourceViewer.frame + 1)
        case .markIn: sourceViewer.markIn()
        case .markOut: sourceViewer.markOut()
        case .sourceInsert: try placeSource(.insert, author: author)
        case .sourceOverwrite: try placeSource(.overwrite, author: author)
        case .sourceClose: sourceViewer.close()
        default: assertionFailure("Unhandled UI action \(action.id)")
        }
    }

    func setTimelineZoom(_ value: Double) {
        timelineScale = min(max(value, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
    }

    /// Scrolls the timeline so `frame` is visible.
    func revealInTimeline(_ frame: Int) {
        timelineReveal = TimelineReveal(frame: min(max(0, frame), project.duration))
    }

    // MARK: Automation

    func registerUIActionCommands() {
        handle("ui.actions") { document, _, _ in
            .array(UIAction.allCases.map { action in
                .object([
                    "id": .string(action.id), "title": .string(action.title),
                    "shortcuts": .array(action.shortcuts.map { .string($0.description) }),
                    "enabled": .bool(document.canPerform(action)),
                ])
            })
        }
        handleAuthored("ui.action") { document, arguments, author in
            try document.performFromAutomation(arguments.string("action"), author: author)
        }
        handle("ui.view") { document, arguments, _ in
            try document.updateView(arguments)
            return document.viewStateJSON()
        }
        handle("ui.source") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            guard let media = document.project.media.first(where: { $0.id == mediaID }) else {
                throw RPCFailure(-32602, "Unknown media \(mediaID)")
            }
            document.previewSource(media)
            guard document.sourceViewer.media?.id == mediaID else { throw RPCFailure(-32602, document.message) }
            let last = max(1, media.frames)
            let start = min(arguments.optionalInt("in") ?? 0, last - 1)
            document.sourceViewer.inFrame = start
            document.sourceViewer.outFrame = min(max(start + 1, arguments.optionalInt("out") ?? last), last)
            document.sourceViewer.seek(start)
            return document.viewStateJSON()
        }
    }

    private func performFromAutomation(_ name: String, author: Author) throws -> JSONValue {
        let candidates = UIAction.matching(name)
        guard let first = candidates.first else {
            throw RPCFailure(-32602, "Unknown action or shortcut \(name); see ui.actions")
        }
        if let open = ModalCenter.shared.current {
            throw RPCFailure(-32003, "Answer the open dialog \(open.name) first (ui.dialog)")
        }
        guard let action = candidates.first(where: canPerform) else {
            throw RPCFailure(-32003, "\(first.id) is not available now")
        }
        if action.mayShowModal {
            // The alert or panel blocks until answered; return now so the agent can answer it. Start it from
            // the run loop like a key press: a modal run inside a main-queue job (a Task) would stop the main
            // queue, and with it every automation request, until the dialog closes.
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    do { try self.perform(action, author: author) } catch { self.message = error.localizedDescription }
                }
            }
            return .object(["action": .string(action.id), "started": .bool(true)])
        }
        try perform(action, author: author)
        return .object([
            "action": .string(action.id), "rev": .integer(project.revision), "view": viewStateJSON(),
        ])
    }

    private func updateView(_ arguments: CommandArguments) throws {
        if let zoom = arguments.optionalInt("zoom") { setTimelineZoom(Double(zoom)) }
        if let snap = arguments.optionalBool("snap") { snapping = snap }
        if let safeArea = arguments.optionalBool("safeArea") { showSafeArea = safeArea }
        if let dock = arguments.optionalBool("agentDock") {
            if dock, agents.isDetached { agents.attach() }
            showAgentDock = dock
        }
        if let compare = arguments.optionalBool("compare") {
            guard !compare || project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
            setColorComparison(compare)
        }
        if let frame = arguments.optionalInt("reveal") { revealInTimeline(frame) }
    }

    func viewStateJSON() -> JSONValue {
        var source: JSONValue = .null
        if sourceViewer.visible, let media = sourceViewer.media {
            source = .object([
                "media": .string(media.id), "frame": .integer(sourceViewer.frame),
                "in": .integer(sourceViewer.inFrame), "out": .integer(sourceViewer.outFrame),
                "playing": .bool(sourceViewer.playing),
            ])
        }
        return .object([
            "zoom": .number(timelineScale), "zoomRange": .array([
                .number(Self.timelineZoomRange.lowerBound), .number(Self.timelineZoomRange.upperBound),
            ]),
            "snap": .bool(snapping), "safeArea": .bool(showSafeArea), "compare": .bool(showColorComparison),
            "agentDock": .bool(showAgentDock && !agents.isDetached), "agentDockDetached": .bool(agents.isDetached),
            "playing": .bool(player.rate != 0), "playhead": .integer(playhead),
            "selection": selectedID.map(JSONValue.string) ?? .null,
            "selectedTrack": selectedTrackID.map(JSONValue.string) ?? .null,
            "libraryPanel": .string(libraryTab.rawValue.lowercased()), "source": source,
        ])
    }
}

/// A one-off request for the timeline to scroll a frame into view.
struct TimelineReveal: Equatable {
    let frame: Int
    let id = UUID()
}
