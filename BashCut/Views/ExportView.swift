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
    @State private var preset: ExportPreset = .tiktok
    @State private var directory: URL?
    @State private var includeSubRip = false
    @State private var normalizeAudio = false
    @State private var targetLUFS = -14.0
    @State private var loudnessProvider = ""

    private var dimensions: (Int, Int) {
        preset.dimensions(projectWidth: document.project.width, projectHeight: document.project.height)
    }
    private var issues: Int { TimelineReview.run(document.project).count }
    private var loudnessProviders: [PluginProviderChoice] {
        document.plugins.providers(for: "audio.loudness")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                Picker("Preset", selection: $preset) {
                    ForEach(ExportPreset.allCases) { value in
                        Text(LocalizedStringKey(value.title)).tag(value)
                    }
                }
                LabeledContent("Video") {
                    Text(videoDescription).foregroundStyle(.secondary)
                }
                LabeledContent("Audio") {
                    Text(audioDescription).foregroundStyle(.secondary)
                }
                LabeledContent("Save to") {
                    HStack {
                        Text(directory?.path ?? "Not selected").lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseDirectory).accessibilityLabel("Choose export folder")
                    }
                }
                Toggle("Include .srt captions", isOn: $includeSubRip)
                    .disabled(document.project.tracks.first(where: { $0.role == "captions" })?.items.isEmpty != false)
                Toggle("Normalize audio", isOn: $normalizeAudio)
                    .disabled(loudnessProviders.isEmpty)
                if normalizeAudio {
                    Picker("Loudness provider", selection: $loudnessProvider) {
                        ForEach(loudnessProviders) { choice in
                            Text("\(choice.pluginName) · \(choice.provider.name)").tag(choice.provider.id)
                        }
                    }
                    Stepper(value: $targetLUFS, in: -30 ... -5, step: 1) {
                        LabeledContent("Target loudness") {
                            Text("\(targetLUFS.formatted(.number.precision(.fractionLength(0)))) LUFS")
                        }
                    }
                }
            }.formStyle(.columns)
            if issues > 0 {
                Label("\(issues) review issues still open", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if loudnessProviders.isEmpty {
                Text("Install an audio.loudness plugin to enable two-pass LUFS normalization.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if normalizeAudio {
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
                Button("Export", action: start).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(name.isEmpty || directory == nil)
            }
        }.padding(24).frame(width: 620)
            .onAppear {
                name = defaultName
                directory = document.fileURL?.deletingLastPathComponent().appendingPathComponent("render")
                preset = document.settings.savedExportPreset
                    ?? (document.project.width > document.project.height ? .youtube1080 : .tiktok)
                document.plugins.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
                normalizeAudio = document.project["audio"]?.object["normalizeEnabled"] == .bool(true)
                    && !loudnessProviders.isEmpty
                targetLUFS = document.project.targetLUFS
                let preferred = document.project.preferredProvider(for: "audio.loudness")
                loudnessProvider = loudnessProviders.first(where: { $0.provider.id == preferred })?
                    .provider.id ?? loudnessProviders.first?.provider.id ?? ""
            }
    }

    private var defaultName: String {
        let setup: ProjectSetup = {
            var value = ProjectSetup()
            value.name = document.project.name
            return value
        }()
        return setup.folderName.isEmpty ? "bashcut-export" : setup.folderName
    }

    private var videoDescription: String {
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

    private func start() {
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
            name: name, preset: preset, directory: directory, includeSubRip: includeSubRip,
            normalizeAudio: normalizeAudio)
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
                row("Cuts", Text(report.cutCount.formatted()))
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
