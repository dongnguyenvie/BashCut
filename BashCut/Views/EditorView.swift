import AVKit
import AppKit
import BashCutProject
import SwiftUI

// The editor keeps its major panels together so AppKit timeline and SwiftUI sheets share one document.
// swiftlint:disable:next type_body_length
struct EditorView: View {
    @Bindable var document: ProjectDocument
    @State private var showReview = false
    @State private var showHistory = false
    @State private var showAsk = false
    @State private var showPlugins = false
    @State private var showSettings = false
    @State private var showDoctor = false
    @State private var showSections = false
    @State private var doctor = DoctorModel()
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
                    Button("Show differences") { document.showExternalChanges = true }
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
                if document.showAgentDock {
                    AgentDockView(model: document.agents).frame(minWidth: 330, idealWidth: 370, maxWidth: 500)
                }
            }
            }
            HStack {
                Text(document.message).lineLimit(2).textSelection(.enabled)
                Spacer()
                if document.exporting {
                    ProgressView(value: document.exportProgress).frame(width: 120)
                    Text(document.exportProgress, format: .percent.precision(.fractionLength(0)))
                    Button("Cancel export", action: document.cancelExport)
                } else if document.exportReport != nil {
                    Button("Export report") { document.showExportReport = true }
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
                    show: { document.showAgentChanges = true },
                    undo: document.undoAgentChange,
                    dismiss: document.clearAgentChange)
            }
        }
        .sheet(isPresented: $document.showNewProject) { NewProjectView(document: document) }
        .sheet(isPresented: $document.showExport) { ExportView(document: document) }
        .sheet(isPresented: $document.showExportReport) {
            if let report = document.exportReport { ExportReportView(report: report) }
        }
        .sheet(item: $document.privilegedApproval) { prompt in
            PrivilegedApprovalView(prompt: prompt, resolve: document.resolvePrivilegedApproval)
        }
        .sheet(isPresented: $document.showAgentChanges) {
            if let change = document.agentChange {
                AgentChangesView(
                    change: change, canUndo: document.canUndoAgentChange,
                    jump: { item in
                        guard let current = item.after else { return }
                        document.selectedID = current.id
                        document.selectedTrackID = item.afterTrackID
                        document.seek(current.at)
                        document.showAgentChanges = false
                    }, undo: document.undoAgentChange,
                    done: { document.showAgentChanges = false })
            }
        }
        .sheet(isPresented: $document.showExternalChanges) {
            if let changes = document.externalChanges {
                ExternalChangesView(
                    changes: changes,
                    keepApp: { document.resolveConflict(loadDisk: false) },
                    loadDisk: { document.resolveConflict(loadDisk: true) },
                    done: { document.showExternalChanges = false })
            }
        }
        .sheet(isPresented: $document.showLegacyImportReport) {
            if let report = document.legacyImportReport {
                LegacyEDLImportReportView(
                    report: report, done: { document.showLegacyImportReport = false })
            }
        }
        .sheet(isPresented: $showReview) { review }
        .sheet(isPresented: $showHistory) { history }
        .sheet(isPresented: $showPlugins) {
            PluginManagerView(model: document.plugins, done: { showPlugins = false })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: document.agents, done: { showSettings = false })
        }
        .sheet(isPresented: $showDoctor) {
            DoctorView(
                model: doctor, refresh: runDoctor,
                done: { showDoctor = false })
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                document.autosave()
            }
        }
        .task {
            while !Task.isCancelled {
                document.updatePlayhead()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("BashCut").font(.headline).foregroundStyle(.cyan)
            Text(document.project.name + (document.dirty ? " •" : "")).lineLimit(1).frame(maxWidth: 200)
            Button {
                document.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z").disabled(document.history.undoEntries.isEmpty)
            Button {
                document.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
                document.history.redoEntries.isEmpty)
            Text(
                String(
                    format: "%d × %d · %.2f", document.project.width, document.project.height,
                    document.project.fps.value)
            )
            .font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("New", action: document.newProject).keyboardShortcut("n")
            Button("Open…", action: document.openProject).keyboardShortcut("o")
            Button("Save", action: document.save).keyboardShortcut("s").disabled(
                document.fileURL == nil || document.saving || document.conflict)
            Button("History") { showHistory = true }
            Button("Review") { showReview = true }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button {
                document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
                showPlugins = true
            } label: {
                Label("Plugins", systemImage: "puzzlepiece.extension")
            }
            Button {
                runDoctor()
                showDoctor = true
            } label: {
                Label("Doctor", systemImage: "stethoscope")
            }
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button("Export…", action: document.export).keyboardShortcut("e").disabled(
                document.project.duration == 0 || document.exporting
            )
            .buttonStyle(.borderedProminent)
            Button {
                if document.agents.isDetached {
                    document.agents.attach()
                } else {
                    document.showAgentDock.toggle()
                }
            } label: {
                Label("Agent", systemImage: "sidebar.right")
            }.keyboardShortcut("j")
        }.controlSize(.small).padding(10).disabled(document.busy)
    }
    private func runDoctor() {
        document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
        doctor.run(
            workspace: document.agents.directory,
            projectRoot: document.fileURL?.deletingLastPathComponent(),
            toolsDirectory: document.agents.toolsDirectory,
            plugins: document.plugins.plugins, pluginDiagnostics: document.plugins.diagnostics)
    }
    private var rail: some View {
        VStack(spacing: 4) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    document.libraryTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 16))
                        Text(LocalizedStringKey(tab.rawValue)).font(.system(size: 8))
                    }
                    .frame(width: 48, height: 42)
                    .background(document.libraryTab == tab ? Color.cyan.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(document.libraryTab == tab ? .cyan : .secondary)
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
                        get: { document.showColorComparison },
                        set: { document.setColorComparison($0) })
                ).toggleStyle(.button).font(.caption).disabled(document.project.duration == 0)
                Toggle("Safe area", isOn: $document.showSafeArea).toggleStyle(.button).font(.caption)
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
                    PlayerView(player: document.player)
                    if document.showColorComparison {
                        GeometryReader { geometry in
                            PlayerView(player: document.comparisonPlayer)
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
                    if document.showSafeArea {
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
            HStack(spacing: 8) {
                Button {
                    document.seek(document.playhead - 1)
                } label: {
                    Image(systemName: "backward.end")
                }
                Button {
                    document.togglePlayback()
                } label: {
                    Image(systemName: document.player.rate == 0 ? "play.fill" : "pause.fill")
                }.keyboardShortcut(.space, modifiers: [])
                Button {
                    document.seek(document.playhead + 1)
                } label: {
                    Image(systemName: "forward.end")
                }
                Slider(
                    value: Binding(get: { Double(document.playhead) }, set: { document.seek(Int($0)) }),
                    in: 0...Double(max(1, document.project.duration)))
                Text(
                    String(
                        format: "%.2f / %.2fs", Double(document.playhead) / document.project.fps.value,
                        Double(document.project.duration) / document.project.fps.value)
                ).font(.caption.monospacedDigit())
            }.buttonStyle(.borderless).padding(10)
        }
    }
    private var timelineToolbar: some View {
        HStack(spacing: 10) {
            Text("TIMELINE").font(.caption.bold())
            Button("Split", action: document.split).keyboardShortcut("b").disabled(
                document.selected == nil)
            Button("Delete") { document.delete() }.disabled(document.selected == nil)
            Menu {
                Button("Video Layer") { document.addTrack(kind: "video") }
                Button("Text Layer") { document.addTrack(kind: "text") }
                Button("Audio Layer") { document.addTrack(kind: "audio") }
            } label: {
                Label("Add Layer", systemImage: "rectangle.stack.badge.plus")
            }
            Button {
                document.moveSelectedTrack(by: 1)
            } label: { Image(systemName: "arrow.up") }
                .help("Move selected layer up")
                .disabled(document.selectedTrackID == nil)
            Button {
                document.moveSelectedTrack(by: -1)
            } label: { Image(systemName: "arrow.down") }
                .help("Move selected layer down")
                .disabled(document.selectedTrackID == nil)
            Button(role: .destructive, action: document.deleteSelectedTrack) {
                Image(systemName: "rectangle.stack.badge.minus")
            }
            .help("Delete selected empty layer")
            .disabled(document.selectedTrackID == nil)
            Toggle("Snap", isOn: $document.snapping).toggleStyle(.button)
            Button("Sections") { showSections = true }
                .popover(isPresented: $showSections) {
                    SectionManagerView(
                        document: document, newLabel: $newSectionLabel,
                        done: { showSections = false })
                }
            Button {
                if let root = document.fileURL?.deletingLastPathComponent() {
                    document.waveforms.refresh(media: document.project.media, root: root)
                }
            } label: {
                Image(systemName: "waveform")
            }
            .help("Refresh waveforms")
            .disabled(document.fileURL == nil || document.waveforms.loading)
            if document.waveforms.loading { ProgressView().controlSize(.mini) }
            if !document.waveforms.errors.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help(document.waveforms.errors.values.sorted().joined(separator: "\n"))
            }
            Button("Ask agent") { showAsk = true }.keyboardShortcut("k")
                .popover(isPresented: $showAsk) {
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
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $document.timelineScale, in: 10...140).frame(width: 120)
            Image(systemName: "plus.magnifyingglass")
        }.font(.caption).controlSize(.small).padding(8).disabled(document.busy)
    }
    private func sendAsk() {
        sendingAsk = true
        Task {
            defer { sendingAsk = false }
            do {
                let image = attachAskFrame ? try await document.captureAgentFrame() : nil
                document.showAgentDock = true
                document.agents.sendContext(ask, imageURL: image)
                showAsk = false
            } catch { document.message = error.localizedDescription }
        }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review").font(.title2)
                Spacer()
                Button("Done") { showReview = false }
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
                            document.seek(issue.frame)
                            showReview = false
                        }
                        Button("Ask agent to fix") {
                            document.showAgentDock = true
                            document.agents.sendContext("Fix this review issue: " + issue.detail)
                            showReview = false
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
                Button("Done") { showHistory = false }
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
        }.padding(20).frame(width: 520, height: 360).preferredColorScheme(.dark)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}
