import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

/// The Export sheet's rows: outputs, options, cover and the draft-graphics notice.
extension ExportView {
    /// The project's outputs as checkboxes, each with its picture; without outputs, a preset picker.
    @ViewBuilder var outputRows: some View {
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
    func option(
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

    var coverRow: some View {
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
    private var steps: [ExportStepRun] { document.matchingExportSteps(for: chosen) }

    /// Draft graphics in a final export (#634): the user may export anyway; the notice names the fix and, when a
    /// plugin contributes an export step for them, finalises them and exports in one click.
    var draftNotice: some View {
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
}
