import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import Foundation

/// Editor buttons, menu items and shortcuts run through `run(_:)`; `ui.action` runs the same code for agents (and
/// opens dialogs, library panels and the source viewer, or shows a status message), and `ui.view` reads or sets the
/// view state (zoom, toggles, timeline scroll).
extension ProjectDocument {
    /// Whether the action's button is enabled right now.
    func canPerform(_ action: UIAction) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        guard !busy else { return false }
        let hasProject = fileURL != nil
        let source = sourceViewer.visible && sourceViewer.media != nil
        switch action {
        case .undo: return history.canUndo
        case .redo: return history.canRedo
        case .newProject, .openProject: return !saving
        case .saveProject: return hasProject && !saving && !conflict
        case .closeProject: return hasProject && !saving
        case .importMedia, .refreshWaveforms: return hasProject && !(action == .refreshWaveforms && waveforms.loading)
        case .showExport, .toggleCompare: return project.duration > 0
        case .togglePlayback, .previousFrame, .nextFrame, .backSecond, .forwardSecond, .shuttleBack, .shuttleStop,
             .shuttleForward: return project.duration > 0 && !sourceViewer.visible
        case .zoomIn: return ui.canZoomIn
        case .zoomOut: return ui.canZoomOut
        case .zoomFit: return project.duration > 0
        case .toggleFullScreenPreview: return fullScreenPreview.isOn || (project.duration > 0 && !sourceViewer.visible)
        case .split, .delete, .lift: return selected != nil
        case .freezeFrame, .changeFraming: return selectedItemTrack?.kind == "video"
        case .unlinkAudio: return selected?.linkedItemID != nil
        case .speedUp: return speedTarget.map { $0.speed < (UIAction.speedPresets.last ?? 4) - 0.001 } ?? false
        case .slowDown: return speedTarget.map { $0.speed > (UIAction.speedPresets.first ?? 0.25) + 0.001 } ?? false
        case .resetSpeed: return speedTarget.map { $0.speed != 1 } ?? false
        case .layerUp, .layerDown, .deleteLayer: return selectedTrackID != nil
        case .sourceTogglePlayback, .sourcePreviousFrame, .sourceNextFrame, .markIn, .markOut, .sourceInsert,
            .sourceOverwrite, .sourceClose:
            return source
        case .sourceShow: return !source && sourceViewer.media != nil
        case .showAgentChanges, .dismissAgentChange: return agentChange != nil
        case .undoAgentChange: return canUndoAgentChange
        case .openChatAgent: return !chatAgents.available.isEmpty
        case .dismissAgentKitPrompt: return agents.setupPending && agents.showsSetupCard && !agents.kitSettingUp
        case .showAgentSetup: return agents.setupPending
        case .installAgentSkills: return agents.kitPrompt != nil && !agents.kitSettingUp
        case .installEditingTools:
            return agents.setupChecklist.tools != .notApplicable && !agents.setupChecklist.toolsDone && !plugins.installBusy
        case .restartAgentForKit: return !agents.restartSessions.isEmpty
        case .skipAppUpdate, .remindAppUpdateLater: return showsAppUpdateNotice
        case .openExportOutput, .revealExportOutput:
            return exports.report.map { FileManager.default.fileExists(atPath: $0.receipt.url.path) } ?? false
        case .showExportProgress, .cancelExport: return exports.isRunning
        case .dismissExportNotice: return exports.notice != nil
        case .clearRecentProjects: return !settings.recentProjects.isEmpty
        case .showRunPanel: return hasProject && runPanel.canShow
        case .dismissRunPanel: return runPanel.visible
        case .toggleRunPanel, .toggleFollowAgent: return hasProject
        case .stopAgent: return activity.canStop
        case .fixRunIssues: return (runPanel.result?.issuesLeft ?? 0) > 0 && agents.canDeliver
        case .tryAnotherRecipe: return runPanel.result != nil && agents.canDeliver
        case .selectAll: return project.tracks.contains { !$0.items.isEmpty }
        case .deselect: return !selectedIDs.isEmpty
        case .copyClips, .cutClips, .sendToAgent: return !selectedItems.isEmpty
        case .pasteClips: return hasProject && (clipboard != nil || Self.pasteboardHasClips)
        case .muteClips: return selectedItems.contains { $0.mediaID != nil }
        case .showHistory, .showReview, .showPlugins, .showDoctor, .showSettings, .showAgentKit, .showSections,
            .showCommands, .showAssetSearch, .showBatch, .showShortcuts, .showUpdates, .showAbout,
            .showRecentProjects, .toggleAgentDock, .toggleLibraryPanel, .toggleInspector,
            .askAgent, .openClaudeTerminal, .openCodexTerminal, .openShellTerminal,
            .toggleSafeArea, .toggleSnap, .toggleCompactHeader, .addVideoLayer, .addAdjustmentLayer, .addTextLayer,
            .addAudioLayer:
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
        case .dismissAgentChange:
            if !author.isAgent { recordAgentChangeVerdict(.keep, signal: .dismiss) }
            clearAgentChange()
        case .newProject: newProject()
        case .openProject: openProject()
        case .saveProject: save()
        case .closeProject: closeProject()
        case .importMedia: importMedia()
        case .showHistory, .showReview, .showPlugins, .showDoctor, .showSettings, .showExport, .showExportProgress,
            .showSections, .showCommands, .showShortcuts, .showUpdates:
            try openDialog(String(action.id.dropFirst("show.".count)))
        case .showRecentProjects: try openDialog("recents")
        case .showAssetSearch: showAssetSearch()
        case .showBatch: openBatch()
        case .toggleAgentDock:
            if agents.isDetached { agents.attach() } else { ui.toggleAgentTab() }
        case .toggleLibraryPanel: ui.showLibraryPanel.toggle()
        case .toggleInspector: ui.toggleInspectorTab()
        case .askAgent: agents.openBrief()
        case .openClaudeTerminal, .openCodexTerminal, .openShellTerminal:
            // The dock's + menu: a new tab with its own session token.
            if !agents.isDetached { ui.showAgentDock = true }
            agents.open(AgentProviderID(rawValue: String(action.id.dropFirst("agent.open-".count))))
        case .openChatAgent:
            if !agents.isDetached { ui.showAgentDock = true }
            if let first = chatAgents.available.first { agents.openChat(first.pluginID) }
        case .togglePlayback: preview.togglePlayback()
        case .previousFrame: preview.seek(playhead - 1)
        case .nextFrame: preview.seek(playhead + 1)
        case .backSecond: preview.seek(playhead - Int(project.fps.value.rounded()))
        case .forwardSecond: preview.seek(playhead + Int(project.fps.value.rounded()))
        case .shuttleBack, .shuttleForward: preview.shuttle(forward: action == .shuttleForward)
        case .shuttleStop: preview.pause()
        case .toggleCompare: preview.setColorComparison(!preview.showColorComparison)
        case .toggleSafeArea: ui.showSafeArea.toggle()
        case .toggleFullScreenPreview: fullScreenPreview.toggle(self)
        case .toggleSnap: ui.snapping.toggle()
        case .zoomIn: ui.zoomIn(around: playhead)
        case .zoomOut: ui.zoomOut(around: playhead)
        case .zoomFit: ui.zoomToFit(duration: project.duration, fps: project.fps.value)
        case .toggleCompactHeader:
            setTimelineHeaderWidth(
                ui.timelineHeaderCompact ? EditorUIState.wideTimelineLeading : EditorUIState.compactTimelineLeading)
        case .freezeFrame: toggleFreezeSelected()
        case .unlinkAudio: unlinkSelectedAudio()
        case .speedUp: try stepSpeed(up: true, author: author)
        case .slowDown: try stepSpeed(up: false, author: author)
        case .resetSpeed: try setClipSpeed(1, keepDuration: false, author: author)
        case .changeFraming:
            guard let item = selected else { return }
            patchSelected(ReframePreset.next(after: item).patch, label: "Change framing")
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
        case .addAdjustmentLayer: selectedTrackID = try addLayer(kind: TrackKind.adjustment, author: author).trackID
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
        case .sourceShow:
            preview.pause()
            sourceViewer.reopen()
        case .selectAll: selectAll()
        case .deselect: clearSelection()
        case .copyClips: copySelection()
        case .cutClips: try cutSelection(author: author)
        case .pasteClips: try pasteClipboard(author: author)
        case .muteClips: try toggleMuteSelection(author: author)
        case .sendToAgent: agents.sendToAgent(selectedIDs)
        default: try performOtherAction(action)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func performOtherAction(_ action: UIAction) throws {
        switch action {
        case .showAgentChanges: try openDialog("agent-changes")
        case .showAgentKit:
            ui.settingsSection = "agents"
            try openDialog("settings")
        case .dismissAgentKitPrompt: agents.dismissKitPrompt()
        case .showAgentSetup:
            if !agents.isDetached { ui.showAgentDock = true }
            agents.showSetupCard()
        case .installAgentSkills: agents.setUpKitFromPrompt()
        case .installEditingTools: agents.installStarterTools()
        case .restartAgentForKit: agents.restartTabsForKit()
        case .skipAppUpdate:
            settings.appUpdateDismissed = appUpdate.available?.version
            ui.showUpdates = false
        case .remindAppUpdateLater:
            settings.appUpdateRemindAfter = Date().addingTimeInterval(AppUpdateModel.checkInterval)
            ui.showUpdates = false
        case .showAbout: MainMenu.showAbout()
        case .undoAgentChange: undoAgentChange()
        case .openExportOutput: if let url = exports.report?.receipt.url { NSWorkspace.shared.open(url) }
        case .revealExportOutput:
            if let url = exports.report?.receipt.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .showRunPanel: runPanel.show()
        case .dismissRunPanel: runPanel.dismiss()
        case .toggleRunPanel: runPanel.toggle()
        case .stopAgent: activity.stop()
        case .toggleFollowAgent: activity.setFollow(!activity.follow)
        case .fixRunIssues: try fixRunIssues()
        case .tryAnotherRecipe: try tryAnotherRecipe()
        case .cancelExport: exports.cancelActive()
        case .dismissExportNotice: exports.dismissNotice()
        case .clearRecentProjects: settings.clearRecentProjects()
        default: assertionFailure("Unhandled UI action \(action.id)")
        }
    }

    /// Resizes the timeline's layer header (dragging its edge, `timeline.header-compact`) and remembers the width.
    func setTimelineHeaderWidth(_ width: Double) {
        let range = EditorUIState.timelineLeadingRange
        let width = min(max(width.rounded(), range.lowerBound), range.upperBound)
        guard width != ui.timelineLeading else { return }
        ui.timelineLeading = width
        settings.timelineHeaderWidth = width
    }

    /// Until the user picks a header width, a window of 1280 pt or more shows the layer names and a narrower one
    /// the short IDs. Not remembered, so resizing the window changes it again.
    func adaptTimelineHeader(windowWidth: Double) {
        guard !settings.timelineHeaderWidthChosen else { return }
        ui.timelineLeading = EditorUIState.defaultTimelineLeading(windowWidth: windowWidth)
    }

    /// Scrolls the timeline so `frame` is visible.
    func revealInTimeline(_ frame: Int) { ui.revealInTimeline(frame, duration: project.duration) }

    // MARK: Automation

    func registerUIActionCommands() {
        handle("ui.actions") { document, _, _ in
            .array(UIAction.allCases.map { action in
                .object([
                    "id": .string(action.id), "title": .string(action.title),
                    "shortcuts": .array(action.shortcuts.map { .string($0.description) }),
                    "enabled": .bool(document.canPerform(action)),
                ])
            } + document.plugins.actions.map { action in
                .object([
                    "id": .string(action.id), "title": .string(action.title), "plugin": .string(action.plugin.id),
                    "shortcuts": .array(action.shortcut.map { [.string($0.description)] } ?? []),
                    "enabled": .bool(document.canRunPluginAction(action)),
                ])
            })
        }
        handleAuthored("ui.action") { document, arguments, author in
            let action = try arguments.string("action")
            guard let target = arguments.optionalString("target") else {
                if ["open", "panel", "source", "notify"].contains(action) {
                    throw RPCFailure(-32602, "\(action) needs a target")
                }
                return try document.performFromAutomation(action, author: author)
            }
            switch action {
            case "open": return try document.openDialogFromAutomation(target)
            case "panel":
                if document.toolEntries.contains(where: { $0.id == target && $0.source != .native }) {
                    document.showTool(target)
                    return .bool(true)
                }
                guard let tab = LibraryTab(panelName: target) else { throw RPCFailure(-32602, "Unknown panel \(target)") }
                document.showLibraryTab(tab)
                if let tool = LibraryTab.toolForPanelName(target) { document.showTool(tool) }
                return .bool(true)
            case "source": return try document.showSource(target, in: arguments.optionalInt("in"), out: arguments.optionalInt("out"))
            case "notify":
                document.message = String(target.prefix(2000))
                return .bool(true)
            default: throw RPCFailure(-32602, "\(action) takes no target; a target goes with open, panel, source or notify")
            }
        }
        handle("ui.view") { document, arguments, _ in
            try document.updateView(arguments)
            return document.viewStateJSON()
        }
    }

    /// `ui.action source MEDIA`: the media in the source viewer with in/out marked.
    private func showSource(_ mediaID: String, in inFrame: Int?, out outFrame: Int?) throws -> JSONValue {
        guard let media = project.media.first(where: { $0.id == mediaID }) else {
            throw RPCFailure(-32602, "Unknown media \(mediaID)")
        }
        previewSource(media)
        guard sourceViewer.media?.id == mediaID else { throw RPCFailure(-32602, message) }
        markSource(in: inFrame, out: outFrame)
        return viewStateJSON()
    }

    /// Marks in/out on the media in the source viewer, kept inside it (out after in), and seeks to in.
    func markSource(in inFrame: Int?, out outFrame: Int?) {
        guard let media = sourceViewer.media else { return }
        let last = max(1, media.frames)
        let start = min(max(0, inFrame ?? 0), last - 1)
        sourceViewer.inFrame = start
        sourceViewer.outFrame = min(max(start + 1, outFrame ?? last), last)
        sourceViewer.seek(start)
    }

    private func performFromAutomation(_ name: String, author: Author) throws -> JSONValue {
        let candidates = UIAction.matching(name)
        if let open = ModalCenter.shared.current {
            throw RPCFailure(-32003, "Answer the open dialog \(open.name) first (ui.dialog)", category: .busyDialog)
        }
        guard let first = candidates.first else {
            if let result = try performPluginActionFromAutomation(name, author: author) { return result }
            throw RPCFailure(-32602, "Unknown action or shortcut \(name); see ui.actions")
        }
        guard let action = candidates.first(where: canPerform) else {
            throw RPCFailure(-32003, "\(first.id) is not available now", category: .notAvailableNow)
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
        if let zoom = arguments.optionalInt("zoom") {
            ui.setTimelineZoom(Double(zoom), anchor: arguments.optionalInt("zoomAnchor") ?? playhead)
        }
        if let snap = arguments.optionalBool("snap") { ui.snapping = snap }
        if let safeArea = arguments.optionalBool("safeArea") { ui.showSafeArea = safeArea }
        if let zoom = arguments.optionalString("viewerZoom") { ui.viewerZoom = EditorViewerZoom.scale(zoom) }
        if let dock = arguments.optionalBool("agentDock") {
            if dock, agents.isDetached { agents.attach() }
            ui.showAgentDock = dock
        }
        if let compare = arguments.optionalBool("compare") {
            guard !compare || project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
            preview.setColorComparison(compare)
        }
        if let frame = arguments.optionalInt("reveal") { revealInTimeline(frame) }
        updatePanels(arguments)
    }

    /// Which tab the Inspector and section the Settings sheet and Knowledge window show.
    private func updatePanels(_ arguments: CommandArguments) {
        if let tab = arguments.optionalString("inspector") { ui.inspectorTab = tab }
        if let tab = arguments.optionalString("rightTab").flatMap(RightColumnTab.init(rawValue:)) {
            if tab == .agent, agents.isDetached { agents.attach() }
            ui.selectRightTab(tab)
        }
        if let draft = arguments.optionalString("chatDraft"), let id = agents.chatPluginID {
            chatAgents.model(for: id).draft = draft
        }
        if let section = arguments.optionalString("settingsSection") { ui.settingsSection = section }
        if let search = arguments.optionalString("settingsSearch") { ui.settingsSearch = search }
        if let section = arguments.optionalString("knowledgeSection") { ui.knowledgeSection = section }
        if let source = arguments.optionalString("mediaSource") { ui.mediaSource = source }
        if let tab = arguments.optionalString("pluginsTab").flatMap(PluginSheetTab.init(rawValue:)) { plugins.tab = tab }
        if let category = arguments.optionalString("pluginsCategory") {
            plugins.browseCategory = PluginCategory(rawValue: category)
        }
        updateLibraryFilter(arguments)
        updateLibraryLayout(arguments)
    }

    /// The open library panel's search and filters.
    private func updateLibraryFilter(_ arguments: CommandArguments) {
        let panel = ui.libraryTab.panelName
        var filter = ui.libraryFilters[panel] ?? LibraryPanelFilter()
        if let query = arguments.optionalString("libraryQuery") { filter.query = query }
        if let pack = arguments.optionalString("libraryPack") { filter.pack = pack.isEmpty ? nil : pack }
        if let tag = arguments.optionalString("libraryTag") { filter.tag = tag.isEmpty ? nil : tag }
        if let scope = arguments.optionalString("libraryScope") { filter.scope = scope == "all" ? nil : scope }
        if let source = arguments.optionalString("librarySource") { filter.source = source == "all" ? nil : source }
        if let collection = arguments.optionalString("libraryCollection") {
            filter.collection = collection == "all" ? nil : collection
        }
        ui.libraryFilters[panel] = filter
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
            "zoom": .number(ui.timelineScale), "zoomRange": .array([
                .number(EditorUIState.timelineZoomRange.lowerBound), .number(EditorUIState.timelineZoomRange.upperBound),
            ]),
            "viewerZoom": .string(EditorViewerZoom.choice(ui.viewerZoom)),
            "snap": .bool(ui.snapping), "headerCompact": .bool(ui.timelineHeaderCompact),
            "headerWidth": .number(ui.timelineLeading), "safeArea": .bool(ui.showSafeArea), "compare": .bool(preview.showColorComparison),
            "fullScreen": .bool(fullScreenPreview.isOn),
            "agentDock": .bool(ui.showAgentDock && !agents.isDetached),
            "agentDockDetached": .bool(agents.isDetached),
            "libraryPane": .bool(ui.showLibraryPanel), "inspectorPane": .bool(ui.inspectorShown),
            "chatTab": agents.chatPluginID.map(JSONValue.string) ?? .null,
            "agentSetup": agents.setupJSON,
            "playing": .bool(preview.isPlaying), "playhead": .integer(playhead),
            "selection": selectedID.map(JSONValue.string) ?? .null,
            "selectedItems": .array(selectedIDs.map(JSONValue.string)),
            "selectedTrack": selectedTrackID.map(JSONValue.string) ?? .null,
            "libraryPanel": .string(ui.libraryTab.panelName), "libraryFilter": libraryFilterJSON(),
            "tool": ui.libraryTab == .tools ? selectedTool.map { .string($0.id) } ?? .null : .null,
            "mediaSource": .string(ui.mediaSource),
            "libraryLayout": .object(libraryLayoutJSON()),
            "inspector": .string(ui.inspectorTab),
            "settingsSection": .string(ui.settingsSection), "settingsSearch": .string(ui.settingsSearch),
            "knowledgeSection": .string(ui.knowledgeSection),
            "pluginsTab": .string(plugins.tab.rawValue),
            "pluginsCategory": .string(plugins.browseCategory?.rawValue ?? "all"),
            "source": source,
        ])
    }

    private func libraryFilterJSON() -> JSONValue {
        let filter = ui.libraryFilters[ui.libraryTab.panelName] ?? LibraryPanelFilter()
        return .object([
            "query": .string(filter.query), "pack": filter.pack.map(JSONValue.string) ?? .null,
            "tag": filter.tag.map(JSONValue.string) ?? .null, "scope": .string(filter.scope ?? "all"),
            "source": .string(filter.source ?? "all"), "collection": .string(filter.collection ?? "all"),
        ])
    }
}
