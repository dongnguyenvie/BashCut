import BashCutProject
import Foundation

/// What the Inspector shows for the selected item (P1-7): the kind decides the tabs and the header's second line.
/// The kind comes from the layer and the media, so a graphic (a still, or a rendered overlay without sound) has no
/// Audio, Text or Speed tab.
public enum InspectorItemKind: Equatable, Sendable {
    case clip, graphic, text, caption, audio, adjustment

    public init(item: Item, track: Track?, media: Media?) {
        if track?.isAdjustment == true {
            self = .adjustment
        } else if track?.kind == TrackKind.audio || media?.kind == "audio" {
            self = .audio
        } else if track?.kind == TrackKind.text || (item.mediaID == nil && !item.text.isEmpty) {
            self = track?.role == TrackRole.captions ? .caption : .text
        } else if media?.isImage == true || (track?.role == TrackRole.overlay && media?.hasAudio != true) {
            self = .graphic
        } else {
            self = .clip
        }
    }

    /// The tabs that apply, in order (`ui view --inspector` names).
    public var tabs: [String] {
        switch self {
        case .clip: ["video", "audio", "color", "speed"]
        case .graphic: ["video", "color"]
        case .text, .caption: ["text", "video"]
        case .audio: ["audio", "speed"]
        case .adjustment: ["color"]
        }
    }
}
