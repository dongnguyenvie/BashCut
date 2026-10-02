import BashCutProject
import SwiftUI

struct SourceViewer: View {
    @Bindable var document: ProjectDocument
    @Bindable var source: SourceViewerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SOURCE").font(.caption.bold()).foregroundStyle(.cyan)
                Text(source.media.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "")
                    .font(.caption).lineLimit(1)
                Spacer()
                Button("Timeline") { source.close() }.font(.caption)
            }.padding(8)
            if let media = source.media {
                HStack(spacing: 10) {
                    if let width = media.width, let height = media.height {
                        Text("\(width) × \(height)")
                    }
                    Text(String(format: "%.2f fps", media.fps.value))
                    Text(String(format: "%.2fs", media.durationSeconds))
                    if media.hasAudio == true { Label("Audio", systemImage: "speaker.wave.2") }
                    Spacer()
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            PlayerView(player: source.player).background(.black)
            HStack(spacing: 8) {
                Button {
                    source.seek(source.frame - 1)
                } label: {
                    Image(systemName: "backward.end")
                }
                Button {
                    source.togglePlayback()
                } label: {
                    Image(systemName: source.playing ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                Button {
                    source.seek(source.frame + 1)
                } label: {
                    Image(systemName: "forward.end")
                }
                Slider(
                    value: Binding(get: { Double(source.frame) }, set: { source.seek(Int($0)) }),
                    in: 0...Double(max(1, (source.media?.frames ?? 1) - 1))
                )
                .accessibilityLabel("Source playhead")
            }.buttonStyle(.borderless).padding(8)
            HStack {
                Button("In") { source.markIn() }.keyboardShortcut("i", modifiers: [])
                Text("\(source.inFrame)").monospacedDigit()
                Button("Out") { source.markOut() }.keyboardShortcut("o", modifiers: [])
                Text("\(source.outFrame)").monospacedDigit()
                Spacer()
                Button("Insert") { document.placeSource(.insert) }.keyboardShortcut("e", modifiers: [])
                Button("Overwrite") { document.placeSource(.overwrite) }.keyboardShortcut(
                    "q", modifiers: [])
            }.font(.caption).controlSize(.small).padding(8)
            if !source.error.isEmpty {
                Text(source.error).foregroundStyle(.orange).font(.caption).padding(8)
            }
        }
        .task {
            while !Task.isCancelled {
                source.update()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
}
