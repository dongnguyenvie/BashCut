import AVFoundation
import BashCutEngine
import BashCutProject
import Observation

@MainActor @Observable final class SourceViewerModel {
    let player = AVPlayer()
    var media: Media?
    var frame = 0
    var inFrame = 0
    var outFrame = 1
    var visible = false
    var playing = false
    var error = ""

    func open(_ media: Media, url: URL) {
        self.media = media
        inFrame = 0
        outFrame = media.frames
        frame = 0
        visible = true
        playing = false
        error = ""
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
    func close() {
        player.pause()
        playing = false
        visible = false
    }
    /// Shows the clip last opened again, where it was left.
    func reopen() {
        guard media != nil else { return }
        visible = true
    }
    func reset() {
        close()
        media = nil
        player.replaceCurrentItem(with: nil)
    }
    func seek(_ value: Int) {
        guard let media else { return }
        frame = min(max(0, value), media.frames - 1)
        player.seek(to: media.fps.time(frame), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func markIn() { inFrame = min(frame, outFrame - 1) }
    func markOut() { outFrame = max(inFrame + 1, frame + 1) }
    func togglePlayback() {
        if player.rate == 0 {
            if frame >= (media?.frames ?? 1) - 1 { seek(inFrame) }
            player.play()
        } else {
            player.pause()
        }
        playing = player.rate != 0
    }
    func update() {
        playing = player.rate != 0
        if let itemError = player.currentItem?.error { error = itemError.localizedDescription }
        guard let media, playing, player.currentTime().isNumeric else { return }
        frame = min(media.frames - 1, max(0, media.fps.frame(player.currentTime())))
    }
}
