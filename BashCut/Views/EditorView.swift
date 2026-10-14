import AVKit
import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

// The editor keeps its major panels together so AppKit timeline and SwiftUI sheets share one document.
struct EditorView: View {
    @Bindable var document: ProjectDocument
    @State private var newSectionLabel = ""
    /// The editor's width, for the right column's width (340 from 1680 pt, 300 below).
    @State var windowWidth = 1280.0
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if document.conflict {
                HStack {
                    Text("The project changed on disk")
                    Spacer()
                    Button("Show differences") { document.ui.showExternalChanges = true }
                        .disabled(document.externalChanges == nil)
                    Button("Keep app version") { document.resolveConflict(loadDisk: false) }
                    Button("Load disk version") { document.resolveConflict(loadDisk: true) }
                }.padding(8).background(Color.orange.opacity(0.15))
            }
            if document.fileURL == nil {
                // The dock works before a project is open, so an agent can be asked to create or open one.
                let welcome = WelcomeView(document: document).frame(minWidth: 560, maxHeight: .infinity)
                if document.ui.showAgentDock {
                    HStack(spacing: 0) {
                        welcome
                        Divider()
                        AgentDockView(model: document.agents)
                            .frame(width: EditorLayout.rightColumnWidth(window: windowWidth)).clipped()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    welcome.frame(maxWidth: .infinity)
                }
            } else {
                // Not a split view: a split view keeps its pane's last width and would not let the window shrink
                // below it (#528). The right column has one width per window size (P1-6).
                HStack(spacing: 0) {
                    editorColumn
                    if agentColumn {
                        Divider()
                        RightColumnView(document: document).frame(width: columnWidth).clipped()
                    }
                }
            }
            // Export progress, the save state and the revision are in the toolbar's activity capsule.
            HStack {
                Text(document.message).lineLimit(2).textSelection(.enabled)
                Spacer()
            }.font(.caption).padding(6)
        }
        .onChange(of: document.selectedID) { if document.selectedID != nil { document.ui.itemSelected() } }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { windowWidth = $0 })
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(red: 0.065, green: 0.07, blue: 0.08)).preferredColorScheme(.dark).tint(.cyan)
        .frame(minWidth: minSize.width, minHeight: minSize.height)
        .background(WindowMinSize(size: minSize))
        .overlay {
            if document.ui.showCommands {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.3).onTapGesture { document.ui.showCommands = false }
                    CommandPaletteView { document.ui.showCommands = false }.padding(.top, 90)
                }
            }
            if document.ui.showRecents {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.3).onTapGesture { document.ui.showRecents = false }
                    RecentProjectsView(document: document) { document.ui.showRecents = false }.padding(.top, 90)
                }
            }
        }
        .modifier(PluginSheetPresenter(document: document))
        .sheet(isPresented: Bindable(document.ui).showShortcuts) {
            ShortcutsView { document.ui.showShortcuts = false }
        }
        // Whole percents, so the Dock icon redraws at most 100 times per export.
        .onChange(of: document.exports.isRunning ? Int(document.exports.progress * 100) : nil) { _, percent in
            ExportDockTile.show(percent.map { Double($0) / 100 })
        }
        // The run panel follows the run log: a cheap check every second, a read only when it changed.
        .task(id: document.fileURL) {
            while !Task.isCancelled {
                document.runPanel.refresh()
                document.activity.refreshStatus()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .sheet(isPresented: Bindable(document.ui).showAsk) { AskAgentView(document: document) }
        .sheet(isPresented: Bindable(document.ui).showQuickEdit) { QuickEditSheet(document: document) }
        .sheet(isPresented: Bindable(document.ui).showVoiceClone) { VoiceCloneSheet(document: document) }
        .sheet(isPresented: Bindable(document.ui).showNewProject) { NewProjectView(document: document) }
        .sheet(isPresented: Bindable(document.ui).showExport) { ExportView(document: document) }
        .sheet(isPresented: Bindable(document.ui).showExportReport) {
            if let report = document.exports.report { ExportReportView(report: report, document: document) }
        }
        .sheet(item: $document.privilegedApproval) { prompt in
            PrivilegedApprovalView(prompt: prompt, resolve: document.resolvePrivilegedApproval)
        }
        .sheet(item: $document.checkpoint) { request in
            CheckpointView(request: request, resolve: document.resolveCheckpoint)
        }
        .sheet(item: $document.scopeHold) { hold in
            AgentScopeHoldView(hold: hold, resolve: { document.resolveScopeHold($0) })
        }
        .sheet(isPresented: Bindable(document.ui).showAgentChanges) {
            if let change = document.agentChange {
                AgentChangesView(
                    change: change, canUndo: document.canUndoAgentChange,
                    jump: { item in
                        guard let current = item.after else { return }
                        document.selectedID = current.id
                        document.selectedTrackID = item.afterTrackID
                        document.preview.seek(current.at)
                        document.ui.showAgentChanges = false
                    }, undo: document.undoAgentChange,
                    done: { document.ui.showAgentChanges = false })
            }
        }
        .sheet(isPresented: Bindable(document.ui).showExternalChanges) {
            if let changes = document.externalChanges {
                ExternalChangesView(
                    changes: changes,
                    keepApp: { document.resolveConflict(loadDisk: false) },
                    loadDisk: { document.resolveConflict(loadDisk: true) },
                    done: { document.ui.showExternalChanges = false })
            }
        }
        .sheet(isPresented: Bindable(document.ui).showLegacyImportReport) {
            if let report = document.importReport {
                TimelineImportReportView(
                    report: report, done: { document.ui.showLegacyImportReport = false })
            }
        }
        .sheet(isPresented: Bindable(document.ui).showReview) { review }
        .sheet(isPresented: Bindable(document.ui).showHistory) { history }
        .sheet(isPresented: Bindable(document.ui).showPlugins) {
            PluginManagerView(model: document.plugins, document: document, done: { document.ui.showPlugins = false })
        }
        .sheet(item: Bindable(document.plugins).pendingAction) { _ in
            PluginActionParamsSheet(document: document, model: document.plugins)
        }
        .sheet(item: Binding(get: { document.plugins.confirmations.first }, set: { _ in })) { pending in
            PluginConfirmSheet(pending: pending) { document.resolvePluginConfirm(pending.id, run: $0) }
        }
        .sheet(isPresented: Bindable(document.ui).showPluginProposals) {
            PluginProposalSheet(document: document, model: document.plugins)
        }
        .onChange(of: document.plugins.proposals.isEmpty) {
            if document.plugins.proposals.isEmpty { document.ui.showPluginProposals = false }
        }
        .sheet(isPresented: Bindable(document.ui).showSettings) {
            SettingsView(model: document.agents, document: document, settings: document.settings, done: { document.ui.showSettings = false })
        }
        .sheet(isPresented: Bindable(document.ui).showDoctor) {
            DoctorView(
                model: document.doctor, refresh: runDoctor,
                done: { document.ui.showDoctor = false })
        }
        .onChange(of: document.ui.showDoctor) { if document.ui.showDoctor { runDoctor() } }
        .sheet(isPresented: Bindable(document.ui).showUpdates) {
            AppUpdateView(
                model: document.appUpdate, settings: document.settings,
                check: { Task { await document.appUpdate.check() } },
                update: { document.installAppUpdate() },
                skip: { document.run(.skipAppUpdate) },
                later: { document.run(.remindAppUpdateLater) },
                done: { document.ui.showUpdates = false })
        }
        .onChange(of: document.ui.showUpdates) {
            // Opened by hand: ask GitHub now. Opened by itself: it already knows the release.
            if document.ui.showUpdates, !document.ui.updatesPrompt { Task { await document.appUpdate.check() } }
            if !document.ui.showUpdates { document.ui.updatesPrompt = false }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                document.autosave()
            }
        }
        .task {
            while !Task.isCancelled {
                document.preview.updatePlayhead()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    private func runDoctor() { Task { await document.runDoctor() } }
    private var minSize: CGSize { EditorLayout.minSize(agentColumn: agentColumn || (document.fileURL == nil && document.ui.showAgentDock)) }
    var rail: some View {
        VStack(spacing: 4) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    // The open panel's tab collapses the panel; any other tab shows it.
                    if libraryTabSelected(tab), document.ui.showLibraryPanel {
                        document.run(.toggleLibraryPanel)
                    } else {
                        document.showLibraryTab(tab)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 16))
                        Text(LocalizedStringKey(tab.rawValue)).font(.system(size: 8))
                    }
                    .frame(width: 48, height: 42)
                    .background(libraryTabSelected(tab) ? Color.cyan.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    // Plain buttons only hit-test drawn pixels; make the whole tile clickable.
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(libraryTabSelected(tab) ? .cyan : .secondary)
                    .help(LocalizedStringKey(tab.rawValue))
            }
            pluginRail
            Spacer()
        }.padding(.top, 8)
    }
    var timelineToolbar: some View {
        HStack(spacing: 10) {
            Text("TIMELINE").font(.caption.bold())
            Button("Split") { document.run(.split) }.action(.split, in: document)
            Button("Delete") { document.run(.delete) }.action(.delete, in: document)
            Menu {
                Button("Video Layer") { document.run(.addVideoLayer) }
                Button("Adjustment Layer") { document.run(.addAdjustmentLayer) }
                Button("Text Layer") { document.run(.addTextLayer) }
                Button("Audio Layer") { document.run(.addAudioLayer) }
            } label: {
                Label("Add Layer", systemImage: "rectangle.stack.badge.plus")
            }
            Button {
                document.run(.layerUp)
            } label: { Image(systemName: "arrow.up") }
                .help("Move selected layer up")
                .action(.layerUp, in: document)
            Button {
                document.run(.layerDown)
            } label: { Image(systemName: "arrow.down") }
                .help("Move selected layer down")
                .action(.layerDown, in: document)
            Button(role: .destructive) {
                document.run(.deleteLayer)
            } label: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
            .help("Delete selected empty layer")
            .action(.deleteLayer, in: document)
            Toggle("Snap", isOn: Bindable(document.ui).snapping).toggleStyle(.button)
            Button("Sections") { document.run(.showSections) }
                .popover(isPresented: Bindable(document.ui).showSections) {
                    SectionManagerView(
                        document: document, newLabel: $newSectionLabel,
                        done: { document.ui.showSections = false })
                }
            Button {
                document.run(.refreshWaveforms)
            } label: {
                Image(systemName: "waveform")
            }
            .help("Refresh waveforms")
            .action(.refreshWaveforms, in: document)
            if document.waveforms.loading { ProgressView().controlSize(.mini) }
            if !document.waveforms.errors.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help(document.waveforms.errors.values.sorted().joined(separator: "\n"))
            }
            Button("Ask agent") { document.run(.askAgent) }.shortcut(.askAgent)
            Spacer()
            Button {
                document.run(.zoomOut)
            } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless).help("Zoom timeline out (⌘-)").action(.zoomOut, in: document)
            Slider(
                value: Binding(
                    get: { document.ui.timelineZoomSliderValue },
                    set: { document.ui.setTimelineZoomSliderValue($0, around: document.playhead) }),
                in: EditorUIState.timelineZoomSliderRange
            ).frame(width: 120).help("Timeline zoom; pinch or ⌘-scroll on the timeline")
            Button {
                document.run(.zoomIn)
            } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless).help("Zoom timeline in (⌘=)").action(.zoomIn, in: document)
            Button {
                document.run(.zoomFit)
            } label: { Image(systemName: "arrow.left.and.right.square") }
                .buttonStyle(.borderless).help("Zoom timeline to fit (⇧Z)").disabled(!document.canPerform(.zoomFit))
        }.font(.caption).controlSize(.small).padding(8).disabled(document.busy)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review").font(.title2)
                Spacer()
                Button("Done") { document.ui.showReview = false }
            }
            Text(
                "Review checks the timeline, text placement, the hook and sound. Loudness comes from the last normalized "
                    + "export of this revision."
            ).font(.caption).foregroundStyle(.secondary)
            let issues = document.reviewIssues()
            if issues.isEmpty { Label("No timeline issues found", systemImage: "checkmark.circle") }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issues) { issue in reviewRow(issue) }
                }
            }.frame(maxHeight: 520)
        }.padding(20).frame(width: 560).preferredColorScheme(.dark)
    }
    private var history: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("History").font(.title2)
                Spacer()
                Button("Done") { document.ui.showHistory = false }
            }
            List(Array(document.history.undoEntries.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(entry.label)
                    Spacer()
                    Text(entry.author.rawValue).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Undo", action: document.undo)
                Button("Redo", action: document.redo)
            }
        }.padding(20).frame(width: 520, height: 360, alignment: .top).preferredColorScheme(.dark)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        // An editor preview is not media for Control Center; publishing it made AVKit poll the player item's
        // time on the main thread, which blocked on the decoder during playback.
        view.updatesNowPlayingInfoCenter = false
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
