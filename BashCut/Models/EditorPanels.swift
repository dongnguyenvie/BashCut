import Foundation

enum LibraryTab: String, CaseIterable, Identifiable {
    case media = "Media"
    case audio = "Audio"
    case text = "Text"
    case stickers = "Stickers"
    case effects = "Effects"
    case transitions = "Transitions"
    case filters = "Filters"
    case voice = "Voice"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .media: return "film"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .stickers: return "star"
        case .effects: return "sparkles"
        case .transitions: return "arrow.left.arrow.right"
        case .filters: return "circle.lefthalf.filled"
        case .voice: return "mic"
        }
    }
}
