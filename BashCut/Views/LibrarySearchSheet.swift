import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import SwiftUI

/// A library panel's Search… and Generate… sheet (#81): asks a plugin that provides `library.search` or
/// `library.generate` for items of the panel's kinds, previews the candidates and saves the chosen ones. The same as
/// `library search`, `library generate` and `library add --from-result`.
struct LibrarySearchSheet: View {
    @Bindable var document: ProjectDocument
    @Binding var request: LibrarySearchRequest
    private var preview = LibraryAudioPreview.shared

    init(document: ProjectDocument, request: Binding<LibrarySearchRequest>) {
        self.document = document
        _request = request
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.isGenerate ? "Generate library items" : "Search library items").font(.headline)
            Form {
                if request.kinds.count > 1 {
                    Picker("Kind", selection: $request.kind) {
                        ForEach(request.kinds, id: \.self) { kind in
                            let title = ProjectDocument.kindTitle(kind)
                            Text(verbatim: title.prefix(1).uppercased() + title.dropFirst()).tag(kind)
                        }
                    }
                }
                Picker("Provider", selection: $request.provider) {
                    Text("Automatic").tag(String?.none)
                    ForEach(providers) { choice in
                        Text(verbatim: "\(choice.provider.name) (\(choice.pluginName))").tag(String?.some(choice.provider.id))
                    }
                }
                TextField(
                    request.isGenerate ? "Prompt" : "Search", text: $request.text,
                    prompt: Text(request.isGenerate ? "calm lo-fi beat, 30 seconds" : "rain, cat, applause…"))
                    .onSubmit { document.runLibrarySearchSheet() }
                Picker("Save in", selection: $request.scope) {
                    Text("Project").tag(LibraryScope.project)
                    Text("This Mac").tag(LibraryScope.user)
                }
                .disabled(document.fileURL == nil)
            }
            HStack {
                Button(request.isGenerate ? "Generate" : "Search") { document.runLibrarySearchSheet() }
                    .disabled(request.running || request.text.trimmingCharacters(in: .whitespaces).isEmpty)
                if request.running { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let error = request.error {
                Text(verbatim: error).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(request.candidates.enumerated()), id: \.offset) { index, candidate in
                        row(index, candidate)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 320)
            Text("Candidates come from the plugin and its source; check the license before you use one. Saving copies it into the library.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close", role: .cancel) {
                    preview.stop()
                    document.ui.librarySearch = nil
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 460)
    }

    private var providers: [PluginProviderChoice] { document.libraryProviders(request.capability, kinds: [request.kind]) }

    private func row(_ index: Int, _ candidate: LibraryCandidate) -> some View {
        let reference = "candidate:\(request.jobID ?? ""):\(index)"
        let playing = preview.playing == reference
        return HStack(spacing: 8) {
            if candidate.item.kind == .audio, let file = candidate.fileURL {
                Button {
                    if playing {
                        preview.stop()
                    } else {
                        do { try preview.play(file, reference: reference) } catch { document.message = error.localizedDescription }
                    }
                } label: {
                    Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 14)
                }
                .buttonStyle(.borderless).help(playing ? "Stop" : "Play")
                .accessibilityLabel(playing ? Text("Stop") : Text("Play"))
            } else if let emoji = candidate.item.params["emoji"]?.string {
                Text(verbatim: emoji).font(.title2).frame(width: 40, height: 40)
            } else {
                LibraryImage(url: candidate.previewURL ?? candidate.fileURL).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: candidate.item.name).lineLimit(1)
                Text(verbatim: details(candidate)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if request.saved.contains(index) {
                Label("Saved", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Save") { document.saveLibrarySearchCandidate(index) }
                    .help("Save in the library with its source and license")
            }
        }
        .font(.caption)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
    }

    /// License, source and tags, as given.
    private func details(_ candidate: LibraryCandidate) -> String {
        [candidate.item["license"]?.string, candidate.item["source"]?.string, candidate.item.tags.joined(separator: ", ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
