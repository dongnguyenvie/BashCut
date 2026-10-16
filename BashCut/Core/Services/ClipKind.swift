import BashCutProject
import Foundation

/// What a timeline clip is, which picks its fill colour (P2-B4): footage teal, graphic indigo, text amber, audio
/// green, voice purple, adjustment grey. The layer's role is kept as a thin stripe (`roleStripe`).
public enum ClipKind: String, CaseIterable, Sendable {
    case footage, graphic, text, audio, voice, adjustment

    /// An sRGB colour, 0…1 per channel.
    public struct RGB: Hashable, Sendable {
        public let red: Double, green: Double, blue: Double
        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public init(item: Item, track: Track, media: Media?) {
        switch InspectorItemKind(item: item, track: track, media: media) {
        case .adjustment: self = .adjustment
        case .text, .caption: self = .text
        case .graphic: self = .graphic
        case .audio:
            self = [TrackRole.voiceover, TrackRole.dialogue].contains(track.role) ? .voice : .audio
        case .clip:
            // A plan's graphic row or a rendered overlay with alpha is a graphic even on the main layer.
            let graphic = item["tag"]?.object["role"]?.string == "graphic" || media?["alpha"]?.bool == true
            self = graphic ? .graphic : .footage
        }
    }

    public var color: RGB {
        switch self {
        case .footage: RGB(0.10, 0.55, 0.58)
        case .graphic: RGB(0.30, 0.36, 0.80)
        case .text: RGB(0.85, 0.58, 0.12)
        case .audio: RGB(0.20, 0.58, 0.32)
        case .voice: RGB(0.52, 0.32, 0.78)
        case .adjustment: RGB(0.45, 0.47, 0.50)
        }
    }

    /// The colour of the layer's role, drawn as a stripe along the clip's bottom edge; on the main layer a speech
    /// or under-voiceover shot keeps its own. Nil for adjustment layers and roles BashCut does not assign.
    public static func roleStripe(track: Track, item: Item) -> RGB? {
        guard track.role == TrackRole.main else { return roleColors[track.role] }
        switch item["tag"]?.object["role"]?.string {
        case "speech": return RGB(0.18, 0.45, 0.85)
        case "underVO": return RGB(0.45, 0.32, 0.78)
        default: return RGB(0.10, 0.55, 0.58)
        }
    }

    private static let roleColors: [String: RGB] = [
        TrackRole.overlay: RGB(0.30, 0.36, 0.80), TrackRole.captions: RGB(0.25, 0.70, 0.85),
        TrackRole.titles: RGB(0.90, 0.40, 0.20), TrackRole.dialogue: RGB(0.20, 0.58, 0.32),
        TrackRole.voiceover: RGB(0.10, 0.50, 0.75), TrackRole.music: RGB(0.55, 0.30, 0.70),
        TrackRole.sfx: RGB(0.75, 0.30, 0.50),
    ]

    /// `text` cut in the middle with "…" so it `fits`, keeping the ending ("isom…canvas.mov"): two thirds of the kept
    /// characters come from the end, where a file name says what it is. Empty when not even "…" fits.
    public static func truncatingMiddle(_ text: String, fits: (String) -> Bool) -> String {
        if fits(text) { return text }
        let characters = Array(text)
        func cut(_ kept: Int) -> String {
            String(characters.prefix(kept / 3)) + "…" + String(characters.suffix(kept - kept / 3))
        }
        var low = 0, high = characters.count - 1
        guard fits(cut(0)) else { return "" }
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(cut(mid)) { low = mid } else { high = mid - 1 }
        }
        return cut(low)
    }
}
