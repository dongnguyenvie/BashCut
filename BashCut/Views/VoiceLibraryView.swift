import AVFoundation
import SwiftUI

struct VoiceLibraryView: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var text = ""
    @State private var provider = ""
    @State private var message = ""
    @State private var takes: [GeneratedVoiceTake] = []
    @State private var selectedTake = ""
    @State private var preview = AVPlayer()
    @State private var recorder = VoiceRecorderModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Voiceover", systemImage: "waveform")
            TextEditor(text: $text).frame(minHeight: 90).scrollContentBackground(.hidden)
                .padding(5).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 6))
            providerPicker
            Button(pluginManager.calling.contains("voice.synthesize") ? "Generating…" : "Generate → 3 takes") {
                generate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                document.fileURL == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || pluginManager.calling.contains("voice.synthesize"))
            takeList
            recordingControls
            Button("Import a voiceover take…") { document.importMedia(kind: "audio", trackID: "a2") }
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .task(id: document.fileURL) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            provider = document.project.preferredProvider(for: "voice.synthesize") ?? ""
        }
        .onDisappear {
            discardPending()
            recorder.cancel()
        }
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $provider) {
            Text("Automatic").tag("")
            ForEach(pluginManager.providers(for: "voice.synthesize")) { choice in
                Text("\(choice.provider.name) · \(choice.pluginName)").tag(choice.provider.id)
            }
        }
        .onChange(of: provider) { _, value in
            let stored = document.project.preferredProvider(for: "voice.synthesize") ?? ""
            guard value != stored else { return }
            document.apply(
                .setProviderPreference(
                    capability: "voice.synthesize", provider: value.isEmpty ? nil : value),
                label: "Choose voice provider")
        }
    }

    @ViewBuilder private var takeList: some View {
        if !takes.isEmpty {
            ForEach(Array(takes.enumerated()), id: \.element.id) { index, take in
                takeRow(take, index: index)
            }
            Button("Insert selected take into Voiceover", action: insertSelected)
                .buttonStyle(.borderedProminent).disabled(selectedTake.isEmpty)
        }
    }

    private func takeRow(_ take: GeneratedVoiceTake, index: Int) -> some View {
        HStack(spacing: 8) {
            Button { play(take) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless).accessibilityLabel("Preview take")
            Text("Take \(index + 1)" + (take.id == bestTakeID ? " ★" : ""))
            Spacer()
            Text(score(take)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Button(take.id == selectedTake ? "Selected" : "Use") { selectedTake = take.id }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(6)
        .background(take.id == selectedTake ? Color.cyan.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(take.id == selectedTake ? Color.cyan : Color.secondary.opacity(0.25))
        }
    }

    private var bestTakeID: String? {
        takes.max { lhs, rhs in lhs.score == rhs.score ? lhs.id > rhs.id : lhs.score < rhs.score }?.id
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Button {
                    recorder.recording ? stopRecording() : startRecording()
                } label: {
                    Label(
                        recorder.recording ? "Stop recording" : "Record voiceover",
                        systemImage: recorder.recording ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(.bordered)
                .tint(recorder.recording ? .red : .accentColor)
                .disabled(document.fileURL == nil)
                if recorder.recording {
                    Text(String(format: "%.1fs", recorder.elapsed)).monospacedDigit()
                    ProgressView(value: recorder.level).frame(width: 55)
                }
            }
            if !recorder.error.isEmpty {
                Text(recorder.error).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func score(_ take: GeneratedVoiceTake) -> String {
        let label = take.scoreSource == "provider" ? String(localized: "match") : String(localized: "pace")
        return String(format: "%@ %.0f%% · %.1fs", label, take.score * 100, take.durationSeconds)
    }

    private func generate() {
        guard let root = document.fileURL?.deletingLastPathComponent() else { return }
        discardPending()
        Task {
            do {
                takes = try await pluginManager.synthesizeVoiceTakes(
                    text: text, language: document.project.fields["contentLanguage"]?.string ?? "vi",
                    count: 3, preferredProvider: provider.isEmpty ? nil : provider,
                    outputRoot: root.appendingPathComponent("voiceover/generated", isDirectory: true))
                selectedTake = bestTakeID ?? takes.first?.id ?? ""
                message = String(localized: "Choose a take to insert")
            } catch { message = error.localizedDescription }
        }
    }

    private func play(_ take: GeneratedVoiceTake) {
        preview.replaceCurrentItem(with: AVPlayerItem(url: take.asset.url))
        preview.play()
    }

    private func insertSelected() {
        guard let take = takes.first(where: { $0.id == selectedTake }) else { return }
        preview.pause()
        Task {
            do {
                try await document.addGeneratedVoice(take.asset)
                pluginManager.discardVoiceTakes(takes, keeping: take.asset.url)
                takes = []
                selectedTake = ""
                message = String(localized: "Voiceover inserted")
            } catch { message = error.localizedDescription }
        }
    }

    private func startRecording() {
        guard let root = document.fileURL?.deletingLastPathComponent() else { return }
        preview.pause()
        Task { await recorder.start(projectRoot: root) }
    }

    private func stopRecording() {
        guard let url = recorder.stop() else { return }
        Task {
            do {
                try await document.addRecordedVoice(url)
                message = String(localized: "Voiceover recording inserted")
            } catch {
                try? FileManager.default.removeItem(at: url)
                message = error.localizedDescription
            }
        }
    }

    private func discardPending() {
        preview.pause()
        pluginManager.discardVoiceTakes(takes)
        takes = []
        selectedTake = ""
        message = ""
    }
}
