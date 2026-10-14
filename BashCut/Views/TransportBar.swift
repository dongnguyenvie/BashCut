import BashCutAutomation
import BashCutDocument
import SwiftUI

/// Play controls, position slider and time under the viewer. It is its own view because it reads the playhead,
/// which changes every playback frame: only this bar re-renders, not the whole editor.
struct TransportBar: View {
    let document: ProjectDocument

    var body: some View {
        HStack(spacing: 8) {
            Button {
                document.run(.previousFrame)
            } label: {
                Image(systemName: "backward.end")
            }
            Button {
                document.run(.togglePlayback)
            } label: {
                Image(systemName: !document.preview.isPlaying ? "play.fill" : "pause.fill")
            }.shortcut(.togglePlayback)
            Button {
                document.run(.nextFrame)
            } label: {
                Image(systemName: "forward.end")
            }
            Slider(
                value: Binding(get: { Double(document.playhead) }, set: { document.preview.seek(Int($0)) }),
                in: 0...Double(max(1, document.project.duration)))
            Text(
                Timecode.transportLabel(
                    position: document.playhead, length: document.project.duration, fps: document.project.fps)
            ).font(.caption.monospacedDigit())
            Button {
                document.run(.toggleFullScreenPreview)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Full Screen Preview (⌥⌘F)")
            .disabled(!document.canPerform(.toggleFullScreenPreview))
        }.buttonStyle(.borderless).padding(10)
    }
}
