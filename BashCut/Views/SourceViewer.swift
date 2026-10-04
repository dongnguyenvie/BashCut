import BashCutAutomation
import BashCutProject
import SwiftUI

struct SourceViewer: View {
    @Bindable var document: ProjectDocument
    @Bindable var source: SourceViewerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ViewerModeSwitch(document: document)
                Spacer()
            }.padding(8)
            Text(
                "A Media clip, not on the timeline yet. Mark In and Out, then Insert (E) or Overwrite (Q) at the playhead. Esc: back to the timeline."
            )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 4)
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
                .overlay(Rectangle().strokeBorder(Color.cyan.opacity(0.8), lineWidth: 2))
            HStack(spacing: 8) {
                Button {
                    document.run(.sourcePreviousFrame)
                } label: {
                    Image(systemName: "backward.end")
                }
                Button {
                    document.run(.sourceTogglePlayback)
                } label: {
                    Image(systemName: source.playing ? "pause.fill" : "play.fill")
                }
                .shortcut(.sourceTogglePlayback)
                Button {
                    document.run(.sourceNextFrame)
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
                Button("In") { document.run(.markIn) }.shortcut(.markIn)
                Text("\(source.inFrame)").monospacedDigit()
                Button("Out") { document.run(.markOut) }.shortcut(.markOut)
                Text("\(source.outFrame)").monospacedDigit()
                Spacer()
                Button("Insert") { document.run(.sourceInsert) }.shortcut(.sourceInsert)
                Button("Overwrite") { document.run(.sourceOverwrite) }.shortcut(.sourceOverwrite)
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
