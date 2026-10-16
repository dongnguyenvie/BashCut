import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

struct ExportView: View {
    @Bindable var document: ProjectDocument
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// The preset when the project names no outputs; with outputs, `checked` picks among them (#593).
    @State private var preset: ExportPreset = .tiktok
    @State private var checked: Set<ExportPreset> = []
    @State private var directory: URL?
    @State private var includeSubRip = false
    @State private var normalizeAudio = false
    @State private var withoutMusic = false
    @State private var targetLUFS = -14.0
    @State private var loudnessProvider = ""
    @State private var coverTitle = ""
    @State private var coverPreset = "hook-title"

    /// The project's outputs (`output.presets`), primary first.
    private var outputs: [ExportPreset] { document.outputPresets }
    /// What Export queues, one job each: the checked outputs in the project's order, else the picked preset.
    private var chosen: [ExportPreset] { outputs.isEmpty ? [preset] : outputs.filter(checked.contains) }
    private var issues: Int { document.reviewIssues().filter { $0.severity != .info }.count }
    private var loudnessProviders: [PluginProviderChoice] {
        document.plugins.providers(for: "audio.loudness")
    }
    private var hasCaptions: Bool {
        document.project.tracks.first(where: { $0.role == "captions" })?.items.isEmpty == false
    }
    private var hasMusic: Bool { document.project.tracks.contains { $0.role == TrackRole.music && !$0.items.isEmpty } }
    /// Draft graphics a final export would ship (#634); a quick draft may use them.
    private var drafts: [WorkflowChecklist.GraphicDraft] {
        chosen.contains { $0 != .quickDraft } ? WorkflowChecklist.graphicDrafts(document.project) : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                if let free = suggestedName {
                    HStack(spacing: 8) {
                        Label(
                            String(format: String(localized: "%@ is already exported or queued"), name),
                            systemImage: "exclamationmark.triangle"
                        ).foregroundStyle(.orange)
                        Button(String(format: String(localized: "Use %@"), free)) { name = free }
                    }.font(.caption)
                }
                outputRows
                LabeledContent("Audio") {
                    Text(audioDescription).foregroundStyle(.secondary)
                }
                LabeledContent("Save to") {
                    HStack {
                        Text(directory?.path ?? "Not selected").lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseDirectory).accessibilityLabel("Choose export folder")
                    }
                }
                option("Include .srt captions", isOn: $includeSubRip,
                       reason: hasCaptions ? nil : "No captions on the timeline")
                option("Without music", isOn: $withoutMusic, reason: hasMusic ? nil : "No music on the timeline")
                    .help("The same cut with voice and sound effects only, to add a platform's own sound")
                option("Normalize audio", isOn: $normalizeAudio,
                       reason: loudnessProviders.isEmpty ? "Needs an audio.loudness plugin" : nil) {
                    Button("Find a plugin…", action: findLoudnessPlugin).font(.caption)
                }
                if normalizeAudio {
                    Picker("Loudness provider", selection: $loudnessProvider) {
                        ForEach(loudnessProviders) { choice in
                            Text("\(choice.pluginName) · \(choice.provider.name)").tag(choice.provider.id)
                        }
                    }
                    // A labelled stepper is a form row of its own: its label left the grid's label column.
                    LabeledContent("Target loudness") {
                        HStack(spacing: 6) {
                            Text("\(targetLUFS.formatted(.number.precision(.fractionLength(0)))) LUFS")
                            Stepper("Target loudness", value: $targetLUFS, in: -30 ... -5, step: 1).labelsHidden()
                        }
                    }
                }
                coverRow
            }.formStyle(.columns)
            if !drafts.isEmpty { draftNotice }
            if issues > 0 {
                Label("\(issues) review issues still open", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if normalizeAudio, !loudnessProviders.isEmpty {
                Text("BashCut renders a temporary mix, measures it, applies a true-peak-safe gain, then verifies the final export.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Export OTIO…") {
                    document.exportOTIO()
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { start() } label: {
                    chosen.count > 1 ? Text("Export \(chosen.count) outputs") : Text("Export")
                }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
            }
        }.padding(24).frame(width: 620)
            .onAppear {
                directory = document.fileURL?.deletingLastPathComponent().appendingPathComponent("render")
                // The project's own output (a recipe or the format menu sets it) wins over the Settings default.
                preset = document.outputPresets.first ?? document.settings.savedExportPreset ?? document.primaryExportPreset
                // The primary output is on; the others wait to be checked.
                checked = Set(outputs.prefix(1))
                // The project name, numbered when an earlier export already took it.
                name = directory.map {
                    ExportRequest.availableName(
                        defaultName, presets: chosen, directory: $0, includeSubRip: includeSubRip,
                        reserved: document.exports.queue.reservedOutputs)
                } ?? defaultName
                document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
                normalizeAudio = document.project["audio"]?.object["normalizeEnabled"] == .bool(true)
                    && !loudnessProviders.isEmpty
                targetLUFS = document.project.targetLUFS
                let preferred = document.project.preferredProvider(for: "audio.loudness")
                loudnessProvider = loudnessProviders.first(where: { $0.provider.id == preferred })?
                    .provider.id ?? loudnessProviders.first?.provider.id ?? ""
            }
    }

    /// The project's outputs as checkboxes, each with its picture; without outputs, a preset picker.
    @ViewBuilder private var outputRows: some View {
        if outputs.isEmpty {
            Picker("Preset", selection: $preset) {
                ForEach(ExportPreset.allCases) { value in
                    Text(LocalizedStringKey(value.title)).tag(value)
                }
            }
            LabeledContent("Video") {
                Text(videoDescription(preset)).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("Outputs") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(outputs) { output in
                        VStack(alignment: .leading, spacing: 1) {
                            Toggle(isOn: outputBinding(output)) {
                                HStack(spacing: 6) {
                                    Text(LocalizedStringKey(output.title))
                                    if output == outputs.first {
                                        Text("Primary").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Text(videoDescription(output)).font(.caption).foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                    if chosen.isEmpty {
                        Text("Check at least one output").font(.caption).foregroundStyle(.orange)
                    } else if chosen.count > 1 {
                        Text(String(format: String(localized: "Each output gets its own file: %@"),
                                    chosen.map { ExportRequest.outputName(name, preset: $0, among: chosen) }
                                        .joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }

    private func outputBinding(_ output: ExportPreset) -> Binding<Bool> {
        Binding(get: { checked.contains(output) }, set: { on in
            if on { checked.insert(output) } else { checked.remove(output) }
        })
    }

    /// A checkbox; when `reason` is set it is off and disabled, with the reason on one line under it.
    private func option(
        _ title: LocalizedStringKey, isOn: Binding<Bool>, reason: LocalizedStringKey?,
        @ViewBuilder fix: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: reason == nil ? isOn : .constant(false)).disabled(reason != nil)
            if let reason {
                HStack(spacing: 6) {
                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    fix()
                }.padding(.leading, 20)
            }
        }
    }

    private var coverRow: some View {
        LabeledContent("Cover") {
            // Two lines: one row of field, preset and button squeezed the label in Vietnamese.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // In a columns form a TextField's title becomes a second label and squeezes the field.
                    TextField("Title (optional)", text: $coverTitle, prompt: Text("Title (optional)"))
                        .labelsHidden().frame(minWidth: 120, maxWidth: 220)
                    Picker("Title preset", selection: $coverPreset) {
                        ForEach(TextPreset.all, id: \.self) { Text(verbatim: $0).tag($0) }
                    }.labelsHidden().fixedSize().disabled(coverTitle.isEmpty)
                }
                Button("Save Cover at Playhead") {
                    document.saveCoverAtPlayhead(title: coverTitle, preset: coverPreset)
                }.help("A still of the frame at the playhead for each output's cover aspect, saved in render/")
            }
        }
    }

    /// Plugin export steps (plugin API 12) a final export of the chosen outputs would run first.
    private var steps: [ExportStepRun] {
        ExportStepRun.matching(
            document.plugins.plugins.filter(document.plugins.isReady), project: document.project, presets: chosen)
    }

    /// Draft graphics in a final export (#634): the user may export anyway; the notice names the fix and, when a
    /// plugin contributes an export step for them, finalises them and exports in one click.
    private var draftNotice: some View {
        let command = WorkflowChecklist.graphicDraftFix(document.project, drafts: drafts)
        let steps = steps
        return VStack(alignment: .leading, spacing: 4) {
            Label(drafts.count == 1 ? "1 graphic is a draft" : "\(drafts.count) graphics are drafts",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            if steps.isEmpty {
                Text("Drafts play at fewer frames a second. Ask your agent for the final render, or run:")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(String(format: String(localized: "Drafts play at fewer frames a second. Finalise and export runs %@ first, then exports."),
                            steps.map(\.title).joined(separator: ", ")))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(verbatim: command).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }.controlSize(.small)
                if !steps.isEmpty {
                    Spacer()
                    Button("Finalise and Export") { start(runSteps: true) }
                        .controlSize(.small).disabled(!canStart)
                        .help("Run the plugin's export step on the drafts, then export")
                }
            }
            Text(verbatim: drafts.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(2)
        }.font(.caption)
    }

    private func findLoudnessPlugin() {
        document.ui.showExport = false
        // Let the Export sheet finish closing before the Plugins sheet opens.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            document.showPluginBrowser(capability: "audio.loudness")
        }
    }

    /// A free name to offer when the typed one would overwrite an export on disk or in the queue.
    private var suggestedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let directory, !trimmed.isEmpty else { return nil }
        let reserved = document.exports.queue.reservedOutputs
        let presets = chosen
        guard presets.contains(where: { preset in
            ExportRequest.nameIsTaken(
                ExportRequest.outputName(trimmed, preset: preset, among: presets), preset: preset,
                directory: directory, includeSubRip: includeSubRip, reserved: reserved)
        }) else { return nil }
        return ExportRequest.availableName(
            trimmed, presets: presets, directory: directory, includeSubRip: includeSubRip, reserved: reserved)
    }

    private var defaultName: String {
        let setup: ProjectSetup = {
            var value = ProjectSetup()
            value.name = document.project.name
            return value
        }()
        return setup.folderName.isEmpty ? "bashcut-export" : setup.folderName
    }

    private func videoDescription(_ preset: ExportPreset) -> String {
        let dimensions = preset.dimensions(projectWidth: document.project.width, projectHeight: document.project.height)
        let codec = preset == .proRes422HQ ? "ProRes 422 HQ" : "H.264"
        let rate = preset.videoBitRate.map { " · \($0 / 1_000_000) Mbps" } ?? ""
        let fps = document.project.fps.value.formatted(.number.precision(.fractionLength(2)))
        return "\(dimensions.0) × \(dimensions.1) · \(fps) fps · \(codec)\(rate)"
    }

    private var audioDescription: String {
        guard normalizeAudio, !loudnessProviders.isEmpty else { return "AAC 320 kbps" }
        let target = targetLUFS.formatted(.number.precision(.fractionLength(0...1)))
        return "AAC 320 kbps · \(target) LUFS"
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        if let url = ModalCenter.shared.open(panel, name: "export-directory")?.first { directory = url }
    }

    private var canStart: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && directory != nil && suggestedName == nil && !chosen.isEmpty
    }

    private func start(runSteps: Bool = false) {
        guard let directory else { return }
        var audio = document.project["audio"]?.object ?? [:]
        audio["normalizeEnabled"] = .bool(normalizeAudio)
        audio["targetLUFS"] = .number(targetLUFS)
        var operations: [EditOperation] = []
        if document.project["audio"] != .object(audio) {
            operations.append(.setProjectProperties(patch: ["audio": .object(audio)]))
        }
        if normalizeAudio, !loudnessProvider.isEmpty,
            document.project.preferredProvider(for: "audio.loudness") != loudnessProvider
        {
            operations.append(
                .setProviderPreference(capability: "audio.loudness", provider: loudnessProvider))
        }
        if !operations.isEmpty {
            document.apply(
                .group(label: "Export audio settings", author: .user, ops: operations),
                label: "Export audio settings")
        }
        document.startExport(
            name: name, presets: chosen, directory: directory, includeSubRip: includeSubRip,
            normalizeAudio: normalizeAudio, withoutRoles: withoutMusic ? [TrackRole.music] : [], runSteps: runSteps)
    }
}

struct ExportReportView: View {
    let report: ExportReport
    let document: ProjectDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Export complete", systemImage: "checkmark.circle.fill").font(.title2.bold())
                    .foregroundStyle(.green)
                Spacer()
                Button("Done") { dismiss() }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                row("Preset", Text(LocalizedStringKey(report.preset.title)))
                row("Duration", Text(report.receipt.duration.formatted(.number.precision(.fractionLength(2)))) + Text(" s"))
                row("Cuts", Text(report.cuts.formatted()))
                row("Captions", Text(report.captionCount.formatted()))
                row("Speech coverage", Text(report.speechCoverage, format: .percent.precision(.fractionLength(0))))
                row("File size", Text(ByteCountFormatter.string(fromByteCount: report.receipt.bytes, countStyle: .file)))
                row("LUFS", loudnessText)
                if let gain = report.appliedGainDb {
                    row("Normalization gain", Text(gain.formatted(.number.sign(strategy: .always()))) + Text(" dB"))
                }
                row("SRT", Text(report.includedSubRip ? "Included" : "Not included"))
            }
            if let comparison = report.comparison {
                Divider()
                Text("Compared with previous export").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    row("Duration", signed(comparison.duration, suffix: " s"))
                    row("File size", signedBytes(comparison.bytes))
                    row("Cuts", Text(comparison.cutCount.formatted(.number.sign(strategy: .always()))))
                    row("Captions", Text(comparison.captionCount.formatted(.number.sign(strategy: .always()))))
                    row("Speech coverage", percentagePoints(comparison.speechCoverage))
                    if let loudness = comparison.integratedLUFS {
                        row("LUFS", signed(loudness, suffix: " LU"))
                    }
                }
            }
            Text(report.receipt.url.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(2)
            HStack {
                Button("Open") { document.run(.openExportOutput) }.action(.openExportOutput, in: document)
                Button("Reveal in Finder") { document.run(.revealExportOutput) }
                    .action(.revealExportOutput, in: document)
                Spacer()
            }
        }.padding(24).frame(width: 540)
    }

    private func row(_ label: LocalizedStringKey, _ value: some View) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            value
        }
    }

    @ViewBuilder private var loudnessText: some View {
        if let loudness = report.loudness {
            let integrated = loudness.integratedLUFS.formatted(.number.precision(.fractionLength(1)))
            let peak = loudness.truePeakDbTP.formatted(.number.precision(.fractionLength(1)))
            HStack(spacing: 6) {
                Text("\(integrated) LUFS · \(peak) dBTP")
                if !report.loudnessVerified {
                    Text("Estimated").foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Not measured")
        }
    }

    private func signed(_ value: Double, suffix: String) -> Text {
        Text(value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))))
            + Text(suffix)
    }

    private func signedBytes(_ value: Int64) -> Text {
        let sign = value >= 0 ? "+" : "−"
        let magnitude = value == .min ? .max : abs(value)
        return Text(sign + ByteCountFormatter.string(fromByteCount: magnitude, countStyle: .file))
    }

    private func percentagePoints(_ value: Double) -> Text {
        let points = value * 100
        return Text(points.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
            + Text(" pp")
    }
}
