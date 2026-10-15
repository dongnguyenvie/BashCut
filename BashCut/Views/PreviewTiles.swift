import BashCutEngine
import BashCutProject
import SwiftUI

/// The tile every picture panel shares (P2-B3, N4): a bordered button with the picture over a one-line caption. The
/// built-in transitions and the library's transition presets, looks, effects and text styles all draw it.
struct PictureTile<Picture: View>: View {
    let caption: Text
    let help: Text
    var enabled = true
    let action: () -> Void
    /// The picture; true while the pointer is over the tile (a transition plays then).
    @ViewBuilder let picture: (Bool) -> Picture
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                picture(hovering).frame(height: 44).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                caption.font(.caption2).lineLimit(1).truncationMode(.middle)
            }
            .padding(.vertical, 4).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A transition's preview (`TransitionPreview`): the icon until the clip is rendered, then its middle frame, and the
/// loop while `playing`.
struct TransitionPreviewPicture: View {
    let motion: TransitionMotion
    let easing: String
    let symbol: String
    let playing: Bool
    @State private var url: URL?
    @State private var poster: CGImage?
    @State private var frames: [CGImage] = []
    @State private var started = Date()

    var body: some View {
        Group {
            if playing, !frames.isEmpty {
                SwiftUI.TimelineView(.animation(minimumInterval: 1 / TransitionPreview.fps)) { context in
                    let index = Int(context.date.timeIntervalSince(started) * TransitionPreview.fps) % frames.count
                    still(frames[max(0, index)])
                }
            } else if let poster {
                still(poster)
            } else {
                LibraryTileFallback(symbol: symbol)
            }
        }
        .task(id: key) {
            let found = await TransitionPreviewStore.shared.preview(motion: motion, easing: easing)
            guard !Task.isCancelled else { return }
            url = found
            if let found { poster = await Task.detached { TransitionPreview.poster(found) }.value }
        }
        // Every frame only while hovered: 39 tiles of decoded frames would hold a lot of memory for nothing.
        .task(id: playing && url != nil) {
            guard playing, let url else {
                frames = []
                return
            }
            let loaded = await Task.detached { TransitionPreview.load(url) }.value
            guard !Task.isCancelled else { return }
            started = Date()
            frames = loaded
        }
        .accessibilityHidden(true)
    }

    private var key: String { TransitionPreview.key(motion: motion, easing: easing) }

    private func still(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}

extension TransitionPreviewPicture {
    /// The preview of a transition preset: its own `motion`, else its kind's built-in row, with its easing.
    init?(preset item: LibraryItem, playing: Bool) {
        guard let preset = try? TransitionPreset(params: item.params) else { return nil }
        self.init(
            motion: TransitionMotion.resolved(kind: preset.kind, motion: preset.motion),
            easing: preset.easing ?? TimelineTransition.defaultEasing,
            symbol: TransitionLibraryView.symbol(preset.kind), playing: playing)
    }
}

/// A saved looping preview (`AnimatedPreview`, an effect preset's GIF): its first frame, and the loop while `playing`,
/// like a transition tile (N4). The icon while it loads or when the file will not load.
struct AnimatedPreviewPicture: View {
    let url: URL
    let symbol: String
    let playing: Bool
    @State private var poster: CGImage?
    @State private var frames: [CGImage] = []
    @State private var delay = 0.1
    @State private var started = Date()

    var body: some View {
        Group {
            if playing, frames.count > 1 {
                SwiftUI.TimelineView(.animation(minimumInterval: delay)) { context in
                    let index = Int(context.date.timeIntervalSince(started) / delay) % frames.count
                    still(frames[max(0, index)])
                }
            } else if let poster {
                still(poster)
            } else {
                LibraryTileFallback(symbol: symbol)
            }
        }
        .task(id: url) {
            let url = url
            let found = await Task.detached { AnimatedPreview.firstFrame(url) }.value
            if !Task.isCancelled { poster = found }
        }
        // Every frame only while hovered, as the transition tiles do.
        .task(id: playing) {
            guard playing else {
                frames = []
                return
            }
            let url = url
            let loaded = await Task.detached { AnimatedPreview.frames(url) }.value
            guard !Task.isCancelled else { return }
            started = Date()
            delay = loaded.delay
            frames = loaded.images
        }
        .accessibilityHidden(true)
    }

    private func still(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }

    /// Whether `url` is a picture this draws (a GIF or still); a movie snippet keeps `LibraryImage`'s middle frame.
    static func draws(_ url: URL) -> Bool { !LibrarySticker.videoExtensions.contains(url.pathExtension.lowercased()) }
}
