import AVKit
import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import SwiftUI

// The editor keeps its major panels together so AppKit timeline and SwiftUI sheets share one document.
// swiftlint:disable:next type_body_length
struct EditorView: View {
    @Bindable var document: ProjectDocument
    @State private var ask = ""
    @State private var attachAskFrame = false
    @State private var sendingAsk = false
    @State private var newSectionLabel = ""
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
                WelcomeView(document: document)
            } else {
            HSplitView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        rail.frame(width: 54)
                        Divider()
                        LibraryView(document: document, pluginManager: document.plugins).frame(width: 225)
                        Divider()
                        Group {
                            if document.sourceViewer.visible {
                                SourceViewer(document: document, source: document.sourceViewer)
                            } else {
                                viewer
                            }
                        }.frame(minWidth: 260, maxWidth: .infinity)
                        Divider()
                        InspectorView(document: document).frame(width: 220)
                    }.disabled(document.busy)
                    Divider()
                    timelineToolbar
                    TimelineView(document: document)
                        .help("Option-drag an edge to roll; Command-drag a clip to slip; Shift-Delete to lift.")
                        .frame(height: 300).disabled(document.busy)
                }.frame(minWidth: 850)
                if document.ui.showAgentDock {
                    AgentDockView(model: document.agents).frame(minWidth: 330, idealWidth: 370, maxWidth: 500)
                }
            }
            }
            HStack {
                Text(document.message).lineLimit(2).textSelection(.enabled)
                Spacer()
                if document.exports.isRunning {
                    if let detail = document.exports.queue.detail {
                        Text(detail).lineLimit(1).foregroundStyle(.secondary)
                    }
                    ProgressView(value: document.exports.progress).frame(width: 120)
                    Text(document.exports.progress, format: .percent.precision(.fractionLength(0)))
                    if document.exports.queue.queuedCount > 0 {
                        Text("\(document.exports.queue.queuedCount) queued").foregroundStyle(.secondary)
                    }
                    Button("Cancel export", action: document.exports.cancelActive)
                } else if document.exports.report != nil {
                    Button("Export report") { document.ui.showExportReport = true }
                }
                if document.busy {
                    ProgressView().controlSize(.small)
                }
                Text(String(format: "rev %d", document.project.revision)).foregroundStyle(.secondary)
            }.font(.caption).padding(6)
        }
        .background(Color(red: 0.065, green: 0.07, blue: 0.08)).preferredColorScheme(.dark).tint(.cyan)
        .frame(minWidth: 1280, minHeight: 800)
        .overlay(alignment: .bottomTrailing) {
            if let change = document.agentChange {
                AgentChangeToast(
                    change: change, canUndo: document.canUndoAgentChange,
                    show: { document.run(.showAgentChanges) },
                    undo: { document.run(.undoAgentChange) },
                    dismiss: { document.run(.dismissAgentChange) })
            }
        }
        .sheet(isPresented: Bindable(document.ui).showNewProject) { NewProjectView(document: document) }
        .sheet(isPresented: Bindable(document.ui).showExport) { ExportView(document: document) }
        .sheet(isPresented: Bindable(document.ui).showExportReport) {
            if let report = document.exports.report { ExportReportView(report: report, document: document) }
        }
        .sheet(item: $document.privilegedApproval) { prompt in
            PrivilegedApprovalView(prompt: prompt, resolve: document.resolvePrivilegedApproval)
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
    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("BashCut").font(.headline).foregroundStyle(.cyan)
            Text(document.project.name + (document.dirty ? " •" : "")).lineLimit(1).frame(maxWidth: 200)
            Button {
                document.run(.undo)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .action(.undo, in: document)
            Button {
                document.run(.redo)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .action(.redo, in: document)
            Text(
                String(
                    format: "%d × %d · %.2f", document.project.width, document.project.height,
                    document.project.fps.value)
            )
            .font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("New") { document.run(.newProject) }.action(.newProject, in: document)
            Button("Open…") { document.run(.openProject) }.action(.openProject, in: document)
            Button("Save") { document.run(.saveProject) }.action(.saveProject, in: document)
            Button("History") { document.run(.showHistory) }
            Button("Review") { document.run(.showReview) }.action(.showReview, in: document)
            PluginActionStrip(document: document, placement: "toolbar", compact: true)
            PluginShortcutButtons(document: document)
            if !document.plugins.proposals.isEmpty {
                Button {
                    document.ui.showPluginProposals = true
                } label: {
                    Label("\(document.plugins.proposals.count) plugin edits", systemImage: "puzzlepiece.extension.fill")
                }.foregroundStyle(.orange).help("Review edits plugin hooks proposed")
            }
            Button {
                if !document.plugins.updates.isEmpty { document.plugins.tab = .updates }
                document.run(.showPlugins)
            } label: {
                let updates = document.plugins.updates.count
                Label(updates > 0 ? String(format: String(localized: "Plugins (%d)"), updates) : String(localized: "Plugins"),
                      systemImage: updates > 0 ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
            }.help(document.plugins.updates.isEmpty ? "" : String(localized: "Plugin updates are available"))
            Button {
                document.run(.showDoctor)
            } label: {
                Label("Doctor", systemImage: "stethoscope")
            }
            Button {
                document.run(.showSettings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button("Export…") { document.run(.showExport) }.action(.showExport, in: document)
                .buttonStyle(.borderedProminent)
            Button {
                document.run(.toggleAgentDock)
            } label: {
                Label("Agent", systemImage: "sidebar.right")
            }.action(.toggleAgentDock, in: document)
        }.controlSize(.small).padding(10).disabled(document.busy)
    }
    private func runDoctor() { Task { await document.runDoctor() } }
    private var rail: some View {
        VStack(spacing: 4) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    document.showLibraryTab(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 16))
                        Text(LocalizedStringKey(tab.rawValue)).font(.system(size: 8))
                    }
                    .frame(width: 48, height: 42)
                    .background(document.ui.libraryTab == tab ? Color.cyan.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    // Plain buttons only hit-test drawn pixels; make the whole tile clickable.
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(document.ui.libraryTab == tab ? .cyan : .secondary)
                    .help(LocalizedStringKey(tab.rawValue))
            }
            Spacer()
        }.padding(.top, 8)
    }
    private var viewer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VIEWER").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Toggle(
                    "Compare",
                    isOn: Binding(
                        get: { document.preview.showColorComparison },
                        set: { document.preview.setColorComparison($0) })
                ).toggleStyle(.button).font(.caption).disabled(document.project.duration == 0)
                Toggle("Safe area", isOn: Bindable(document.ui).showSafeArea).toggleStyle(.button).font(.caption)
            }.padding(8)
            ZStack {
                Color.black
                if document.project.duration == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.cyan)
                        Text("Start your next cut").font(.headline)
                        if document.fileURL == nil {
                            Button("New project", action: document.newProject)
                            Button("Open project…", action: document.openProject)
                        } else {
                            Button("Import footage…") { document.importMedia() }
                        }
                    }
                } else {
                    PlayerView(player: document.preview.player)
                    if document.preview.showColorComparison {
                        GeometryReader { geometry in
                            PlayerView(player: document.preview.comparisonPlayer)
                                .mask {
                                    HStack(spacing: 0) {
                                        Rectangle().frame(width: geometry.size.width / 2)
                                        Color.clear
                                    }
                                }
                            Rectangle().fill(.white.opacity(0.9)).frame(width: 1)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            HStack {
                                Text("Before")
                                Spacer()
                                Text("After")
                            }
                            .font(.caption2.bold()).padding(8)
                            .foregroundStyle(.white).shadow(radius: 2)
                        }.allowsHitTesting(false)
                    }
                    if document.ui.showSafeArea {
                        GeometryReader { geo in
                            let aspect = Double(document.project.width) / Double(document.project.height)
                            let height = min(geo.size.height, geo.size.width / aspect)
                            let width = height * aspect
                            ZStack(alignment: .bottomTrailing) {
                                Rectangle().strokeBorder(
                                    .red.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                Rectangle().fill(.red.opacity(0.15)).frame(height: height * 0.16)
                                Rectangle().fill(.red.opacity(0.15)).frame(
                                    width: width * 0.14, height: height * 0.46)
                            }.frame(width: width, height: height).position(
                                x: geo.size.width / 2, y: geo.size.height / 2)
                        }.allowsHitTesting(false)
                    }
                }
            }
            TransportBar(document: document)
        }
    }
    private var timelineToolbar: some View {
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
                .popover(isPresented: Bindable(document.ui).showAsk) {
                    VStack(alignment: .leading) {
                        Text(document.selectedID ?? "Project").font(.caption)
                        TextField("What should the agent do?", text: $ask).frame(width: 300)
                        Toggle("Attach current frame", isOn: $attachAskFrame)
                        Button(sendingAsk ? "Preparing frame…" : "Send context", action: sendAsk)
                            .disabled(
                                sendingAsk
                                    || (document.agents.current == nil && !document.agents.apiVisible))
                    }.padding()
                }
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
    private func sendAsk() {
        sendingAsk = true
        Task {
            defer { sendingAsk = false }
            do {
                let image = attachAskFrame ? try await document.captureAgentFrame() : nil
                document.ui.showAgentDock = true
                document.agents.sendContext(ask, imageURL: image)
                document.ui.showAsk = false
            } catch { document.message = error.localizedDescription }
        }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review").font(.title2)
                Spacer()
                Button("Done") { document.ui.showReview = false }
            }
            Text("Review checks the timeline. Loudness is measured during normalized export; silence analysis is not available yet.").font(
                .caption
            ).foregroundStyle(.secondary)
            let issues = TimelineReview.run(document.project)
            if issues.isEmpty { Label("No timeline issues found", systemImage: "checkmark.circle") }
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.title).font(.headline)
                    Text(issue.detail).font(.caption)
                    HStack {
                        Button("Jump") {
                            document.preview.seek(issue.frame)
                            document.ui.showReview = false
                        }
                        Button("Ask agent to fix") {
                            document.ui.showAgentDock = true
                            document.agents.sendContext("Fix this review issue: " + issue.detail)
                            document.ui.showReview = false
                        }.disabled(document.agents.current == nil && !document.agents.apiVisible)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(
                    .orange.opacity(0.08)
                ).cornerRadius(6)
            }
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
