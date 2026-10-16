import BashCutDocument
import BashCutProject
import SwiftUI

/// Auto captions in the Tools panel (P1-4): the form that was in the Text panel. Run on the selected clip (its part of
/// the source) or on a media file of the project, as a job.
struct CaptionsToolCard: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var source = ""
    @State private var provider = ""
    @State private var replace = true
    @State private var wordStyle = "none"
    @State private var target = ToolTarget.selectedClip
    @State private var jobID: String?
    @State private var message = ""

    private var job: Job? { jobID.flatMap { document.jobs.job($0) } }
    private var running: Bool { job?.isActive == true || pluginManager.calling.contains("captions.transcribe") }

    var body: some View {
        ToolCard(
            title: String(localized: "Auto captions"), icon: "captions.bubble",
            provider: providerBadge(pluginManager, capability: "captions.transcribe", chosen: provider),
            info: "Listens to the speech and writes timed captions on the Captions layer.",
            targets: ToolTarget.supported(by: ToolID.captions), target: $target, advancedCount: 3,
            runTitle: String(localized: "Generate captions"), canRun: canRun, running: running,
            progress: job?.progress, message: message,
            runOnMany: {
                var params: [String: JSONValue] = ["replace": .bool(replace)]
                if wordStyle != "none" { params["wordStyle"] = .string(wordStyle) }
                document.openBatch(BatchRunner.toolStep(ToolID.captions, label: String(localized: "Auto captions"),
                                                        params: params))
            },
            run: generate,
            main: {
                if target == .project {
                    Picker("Media", selection: $source) {
                        ForEach(document.project.media) { Text($0.fileName).tag($0.id) }
                    }
                } else {
                    Text(clipSummary).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Replace existing captions", isOn: $replace)
                ToolProviderPicker(
                    document: document, manager: pluginManager, capability: "captions.transcribe",
                    provider: $provider, label: "Choose transcription provider")
            },
            advanced: {
                Picker("Word by word", selection: $wordStyle) {
                    Text("Off").tag("none")
                    Text("Highlight word").tag("highlight")
                    Text("Karaoke").tag("karaoke")
                    Text("Reveal word by word").tag("reveal")
                }
                ProviderOptionsView(document: document, capability: "captions.transcribe", providerID: provider)
                Menu("Import SRT…") {
                    Button("Add captions…") { document.importCaptions() }
                    Button("Replace captions…") { document.importCaptions(replace: true) }
                }.disabled(document.fileURL == nil)
                Button("Export SRT…", action: document.exportCaptions).disabled(document.fileURL == nil)
            },
            result: {})
        .task(id: document.project.media.map(\.id).joined(separator: ":")) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            provider = document.project.preferredProvider(for: "captions.transcribe") ?? ""
            if !document.project.media.contains(where: { $0.id == source }) { source = document.project.media.first?.id ?? "" }
        }
        .onChange(of: job?.state) { _, state in finished(state) }
    }

    private var clipSummary: String {
        document.selectedClipSource.map { String(format: String(localized: "Clip: %@"), $0.media.fileName) }
            ?? String(localized: "Select a clip with speech on the timeline.")
    }

    private var canRun: Bool {
        guard document.fileURL != nil else { return false }
        return target == .project ? !source.isEmpty : document.selectedClipSource != nil
    }

    private func generate() {
        message = ""
        let clip = target == .selectedClip ? document.selectedClipSource : nil
        let mediaID = clip?.media.id ?? source
        let replace = replace
        let style = wordStyle == "none" ? nil : wordStyle
        Task {
            do {
                let started = try await document.startCapabilityJob("captions.generate", author: .user) { document in
                    let words = try await document.generateCaptions(
                        mediaID: mediaID, replace: replace, wordStyle: style, range: clip?.range, author: .user)
                    return .object(["rev": .integer(document.project.revision), "transcript": .string(words)])
                }
                jobID = started.object["job"]?.string
            } catch { message = error.localizedDescription }
        }
    }

    private func finished(_ state: Job.State?) {
        switch state {
        case .completed: message = String(localized: "Captions generated")
        case .failed: message = job?.error ?? ""
        case .cancelled: message = String(localized: "Cancelled")
        default: break
        }
    }
}
