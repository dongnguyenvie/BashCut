import BashCutDocument
import BashCutProject
import SwiftUI

/// Beat detection in the Tools panel (P1-4): the form that was in the Audio panel. Run on the selected audio clip or on
/// an audio file of the project, as a job.
struct BeatsToolCard: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var source = ""
    @State private var provider = ""
    @State private var target = ToolTarget.selectedClip
    @State private var jobID: String?
    @State private var message = ""

    private var job: Job? { jobID.flatMap { document.jobs.job($0) } }
    private var running: Bool { job?.isActive == true || pluginManager.calling.contains("audio.beats") }
    private var audio: [Media] { document.project.media.filter { $0["kind"] == .string("audio") } }
    private var clip: Media? {
        document.selectedClipSource.map(\.media).flatMap { $0["kind"] == .string("audio") ? $0 : nil }
    }

    var body: some View {
        ToolCard(
            title: String(localized: "Beat detection"), icon: "metronome",
            provider: providerBadge(pluginManager, capability: "audio.beats", chosen: provider),
            info: "Finds the beats of a song and marks them on the timeline, so cuts can snap to them.",
            targets: ToolTarget.supported(by: ToolID.beats), target: $target, advancedCount: 1,
            runTitle: String(localized: "Detect beats"), canRun: canRun, running: running,
            progress: job?.progress, message: message,
            runOnMany: {
                document.openBatch(BatchRunner.toolStep(ToolID.beats, label: String(localized: "Beat detection")))
            },
            run: detect,
            main: {
                if target == .project {
                    if audio.isEmpty {
                        Text("Import an audio file to detect beats.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Audio", selection: $source) { ForEach(audio) { Text($0.fileName).tag($0.id) } }
                    }
                } else {
                    Text(clip.map { String(format: String(localized: "Clip: %@"), $0.fileName) }
                        ?? String(localized: "Select an audio clip on the timeline."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ToolProviderPicker(
                    document: document, manager: pluginManager, capability: "audio.beats", provider: $provider,
                    label: "Choose beat provider")
                if let bpm = document.project.beatBPM {
                    Text("\(document.project.beatFrames.count) beats · \(bpm, format: .number.precision(.fractionLength(1))) BPM")
                        .font(.caption.monospacedDigit())
                }
            },
            advanced: { ProviderOptionsView(document: document, capability: "audio.beats", providerID: provider) },
            result: {})
        .task(id: document.project.media.map(\.id).joined(separator: ":")) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            provider = document.project.preferredProvider(for: "audio.beats") ?? ""
            if !audio.contains(where: { $0.id == source }) { source = audio.first?.id ?? "" }
        }
        .onChange(of: job?.state) { _, state in finished(state) }
    }

    private var canRun: Bool {
        guard document.fileURL != nil else { return false }
        return target == .project ? !source.isEmpty : clip != nil
    }

    private func detect() {
        message = ""
        let mediaID = target == .project ? source : clip?.id ?? ""
        Task {
            do {
                let started = try await document.startCapabilityJob("beats.detect", author: .user) { document in
                    try await document.detectBeats(mediaID: mediaID, author: .user)
                    return .object(["rev": .integer(document.project.revision)])
                }
                jobID = started.object["job"]?.string
            } catch { message = error.localizedDescription }
        }
    }

    private func finished(_ state: Job.State?) {
        switch state {
        case .completed: message = String(localized: "Beat grid updated")
        case .failed: message = job?.error ?? ""
        case .cancelled: message = String(localized: "Cancelled")
        default: break
        }
    }
}
