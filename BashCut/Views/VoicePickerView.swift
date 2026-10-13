import BashCutPlugin
import BashCutStorage
import SwiftUI

/// The project's voice (#532): My voices (saved clones) first, then each provider's presets, each labelled
/// "Name · Clone|Preset · Plugin". Choosing one is `voice use`; "+ Clone a voice…" opens the clone sheet.
struct VoicePickerView: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var clones: [VoiceClone] = []
    @State private var selection = ""
    @State private var confirmRemove = false

    private var providers: [PluginProviderChoice] { pluginManager.providers(for: "voice.synthesize") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Voice", selection: $selection) {
                Text("Plugin default").tag("")
                if !clones.isEmpty {
                    Section("My voices") {
                        ForEach(clones) { clone in Text(cloneLabel(clone)).tag(clone.id) }
                    }
                }
                ForEach(providers.filter { !($0.provider.voices ?? []).isEmpty }, id: \.provider.id) { choice in
                    Section(choice.pluginName) {
                        ForEach(choice.provider.voices ?? [], id: \.id) { voice in
                            Text(presetLabel(voice.id, plugin: choice.pluginName)).tag(choice.provider.id + "/" + voice.id)
                        }
                    }
                }
            }
            .onChange(of: selection) { _, value in choose(value) }
            HStack {
                Button("+ Clone a voice…") { document.ui.showVoiceClone = true }
                    .disabled(document.fileURL == nil || !providers.contains { $0.provider.cloneRange != nil })
                if selection.hasPrefix("clone-") {
                    Button("Remove voice…", role: .destructive) { confirmRemove = true }
                }
            }
            .controlSize(.small)
        }
        .task(id: document.ui.showVoiceClone) { reload() }
        .task(id: document.project.revision) { selection = current }
        .confirmationDialog("Remove this voice from My voices in every project?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { remove(selection) }
        }
    }

    private func cloneLabel(_ clone: VoiceClone) -> String {
        let plugin = providers.first { ProjectDocument.canSpeak(clone, with: $0.provider) }?.pluginName
        return [clone.name, String(localized: "voice-badge-clone", defaultValue: "Clone"), plugin].compactMap { $0 }.joined(separator: " · ")
    }

    private func presetLabel(_ voice: String, plugin: String) -> String {
        [voice, String(localized: "voice-badge-preset", defaultValue: "Preset"), plugin].joined(separator: " · ")
    }

    /// The project's clone, else the preferred provider's `voice` option.
    private var current: String {
        if let clone = document.projectVoiceClone { return clone.id }
        let preferred = document.project.preferredProvider(for: "voice.synthesize")
        guard let choice = providers.first(where: { $0.provider.id == preferred }) ?? providers.first,
            let plugin = pluginManager.plugins.first(where: { $0.id == choice.pluginID }),
            let voice = document.pluginOptionValues(plugin)["voice"]?.string,
            (choice.provider.voices ?? []).contains(where: { $0.id == voice })
        else { return "" }
        return choice.provider.id + "/" + voice
    }

    private func reload() {
        clones = document.voiceClones.list()
        selection = current
    }

    private func choose(_ value: String) {
        guard value != current else { return }
        do {
            _ = try document.useVoice(value.isEmpty ? "default" : value, author: .user)
        } catch {
            document.message = error.localizedDescription
            selection = current
        }
    }

    private func remove(_ id: String) {
        do {
            try document.removeVoiceClone(id, author: .user)
        } catch { document.message = error.localizedDescription }
        reload()
    }
}
