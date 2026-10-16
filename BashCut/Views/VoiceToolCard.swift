import AVFoundation
import BashCutPlugins
import BashCutProject
import BashCutDocument
import SwiftUI

/// Voiceover in the Tools panel (P1-4): the generator that was the Voice panel. Generates takes from a script and
/// inserts the chosen one into the Voiceover layer; the takes and the recording controls are the result.
struct VoiceToolCard: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var text = ""
    @State private var provider = ""
    @State private var message = ""
    @State private var takes: [GeneratedVoiceTake] = []
    @State private var selectedTake = ""
    @State private var preview = AVPlayer()
    @State private var recorder = VoiceRecorderModel()
    @State private var target = ToolTarget.project

    private var generating: Bool { pluginManager.calling.contains("voice.synthesize") }

    var body: some View {
        ToolCard(
            title: String(localized: "Voiceover"), icon: "waveform",
            provider: providerBadge(pluginManager, capability: "voice.synthesize", chosen: provider),
            info: "Turns a script into spoken takes. Pick the best take and it goes onto the Voiceover layer at the playhead.",
            targets: ToolTarget.supported(by: ToolID.voice), target: $target, advancedCount: 2,
            runTitle: takeCount == 1 ? String(localized: "Generate → 1 take") : String(localized: "Generate → 3 takes"),
            canRun: document.fileURL != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            running: generating, message: message,
            runOnMany: {
                document.openBatch(BatchRunner.toolStep(
                    ToolID.voice, label: String(localized: "Voiceover"),
                    params: ["text": .string(text), "takes": .integer(takeCount), "choose": .integer(1)]))
            },
            run: generate,
            main: {
                Text("Script").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 90).scrollContentBackground(.hidden)
                    .padding(5).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 6))
                providerPicker
                VoicePickerView(document: document, pluginManager: pluginManager)
            },
            advanced: {
                ProviderOptionsView(document: document, capability: "voice.synthesize", providerID: provider)
                Button("Import a voiceover take…") {
                    if let track = voiceoverTrackID { document.importMedia(kind: "audio", trackID: track) }
                }.disabled(voiceoverTrackID == nil)
            },
            result: {
                takeList
                recordingControls
            })
        .task(id: document.fileURL) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            provider = document.project.preferredProvider(for: "voice.synthesize") ?? ""
        }
        .onDisappear {
            discardPending()
            recorder.cancel()
        }
    }

    private var voiceoverTrackID: String? {
        document.project.track(role: TrackRole.voiceover, kind: "audio")?.id
    }

    @ViewBuilder private var providerPicker: some View {
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
        FindPluginButton(document: document, capability: "voice.synthesize")
    }

    /// Takes the chosen provider (or the automatic one, the highest priority) gives per line: 3, or its `maxTakes`.
    private var takeCount: Int {
        let choices = pluginManager.providers(for: "voice.synthesize")
        let chosen = choices.first { $0.provider.id == provider } ?? choices.first
        return chosen?.provider.takes(3) ?? 3
    }

    @ViewBuilder private var takeList: some View {
        if takes.count == 1, let take = takes.first {
            // One take (a provider with maxTakes 1): nothing to choose.
            HStack(spacing: 8) {
                Button { play(take) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("Preview take")
                Spacer()
                Text(score(take)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Button("Insert take into Voiceover", action: insertSelected).buttonStyle(.borderedProminent)
        } else if !takes.isEmpty {
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

    private var bestTakeID: String? { takes.best?.id }

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
        guard let score = take.score else { return String(format: "%.1fs", take.durationSeconds) }
        return String(format: "%@ %.0f%% · %.1fs", String(localized: "match"), score * 100, take.durationSeconds)
    }

    private func generate() {
        discardPending()
        Task {
            do {
                // The user generates here and chose any clone reference themselves.
                takes = try await document.generateVoiceTakes(text: text, count: takeCount, cloneConsent: true)
                selectedTake = bestTakeID ?? takes.first?.id ?? ""
                message = takes.count == 1 ? "" : String(localized: "Choose a take to insert")
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
                try await document.insertVoiceTake(take.asset)
                CapabilityService.discardVoiceTakes(takes, keeping: take.asset.url)
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
        CapabilityService.discardVoiceTakes(takes)
        takes = []
        selectedTake = ""
        message = ""
    }
}
