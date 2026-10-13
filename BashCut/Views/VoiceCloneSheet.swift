import AppKit
import BashCutDocument
import BashCutStorage
import SwiftUI
import UniformTypeIdentifiers

/// Voice panel › Clone a voice… (#532): pick a source (record now, a file, the selected clip), see the window BashCut
/// chose and its checks, preview it, agree, name it and save it to My voices.
struct VoiceCloneSheet: View {
    @Bindable var document: ProjectDocument
    @Bindable var draft: VoiceCloneDraft

    init(document: ProjectDocument) {
        self.document = document
        draft = document.voiceClone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clone a voice").font(.headline)
            Text("Use a few seconds of one person speaking clearly, with no music under the voice.")
                .font(.caption).foregroundStyle(.secondary)
            sourceButtons
            results
            Divider()
            Toggle("I agree to clone this voice", isOn: $draft.consent)
            Picker("Consent", selection: $draft.statement) {
                Text("It is my own voice").tag(VoiceConsentStatement.own)
                Text("I have the speaker's permission").tag(VoiceConsentStatement.permission)
            }
            .pickerStyle(.radioGroup).disabled(!draft.consent)
            TextField("Name", text: $draft.name)
            HStack {
                Button("Preview") { draft.preview(document) }
                    .disabled(draft.prepared == nil || !draft.consent || draft.working)
                if draft.working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Save") { if draft.save(document) { document.ui.showVoiceClone = false } }
                    .keyboardShortcut(.defaultAction).disabled(!draft.canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var sourceButtons: some View {
        HStack {
            Button {
                draft.toggleRecording(document)
            } label: {
                Label(draft.recorder.recording ? "Stop recording" : "Record now",
                      systemImage: draft.recorder.recording ? "stop.circle.fill" : "record.circle")
            }
            .tint(draft.recorder.recording ? .red : .accentColor)
            Button("Choose a file…") { chooseFile() }
            Button("Selected clip") { draft.useSelectedClip(document) }.disabled(document.selectedItems.isEmpty)
        }
        .disabled(draft.working)
    }

    @ViewBuilder private var results: some View {
        if draft.recorder.recording {
            Text(String(format: "%.1fs", draft.recorder.elapsed)).monospacedDigit()
        }
        if !draft.recorder.error.isEmpty { Text(draft.recorder.error).font(.caption).foregroundStyle(.orange) }
        if !draft.sourceTitle.isEmpty { Text(draft.sourceTitle).font(.caption) }
        if let prepared = draft.prepared {
            Text(String(format: String(localized: "Uses %.1f–%.1f s (%.1f s)"),
                        prepared.trim.start, prepared.trim.end, prepared.trim.seconds))
            ForEach(prepared.trim.checks, id: \.id) { check in
                Label(check.detail, systemImage: check.passed ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(check.passed ? Color.secondary : Color.orange)
            }
            Text("A second speaker is not checked.").font(.caption2).foregroundStyle(.secondary)
        }
        if !draft.message.isEmpty { Text(draft.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        ForEach(draft.refusedChecks, id: \.self) { detail in
            Label(detail, systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        guard let url = ModalCenter.shared.open(panel, name: "voice-clone-source")?.first else { return }
        draft.useFile(url, document: document)
    }

    private func close() {
        draft.reset()
        document.ui.showVoiceClone = false
    }
}
