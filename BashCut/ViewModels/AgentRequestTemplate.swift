import Foundation

/// A starting point for a request in the Ask agent sheet; the user fills in the parts in [brackets].
struct AgentRequestTemplate: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let text: String

    static var all: [AgentRequestTemplate] {
        [
            AgentRequestTemplate(
                id: "vlog", title: String(localized: "Vlog"), systemImage: "figure.walk",
                text: String(localized: """
                    I want a vlog about [topic], about [length] long, with a [fun / chill / cinematic] feel.
                    The footage shows [what was filmed]. Music: [style, or none].
                    """)),
            AgentRequestTemplate(
                id: "short", title: String(localized: "Short video"), systemImage: "iphone",
                text: String(localized: """
                    Make a [15–60] second vertical video about [topic] for [TikTok / Reels / Shorts], \
                    with a strong hook in the first 2 seconds and large captions.
                    """)),
            AgentRequestTemplate(
                id: "review", title: String(localized: "Product review"), systemImage: "shippingbox",
                text: String(localized: """
                    Edit a review of [product]: an intro, [3] main points and a verdict, under [length]. \
                    Put a short title on screen for each point.
                    """)),
            AgentRequestTemplate(
                id: "montage", title: String(localized: "Music montage"), systemImage: "music.note",
                text: String(localized: """
                    Make a montage cut to the beat of [song or music style] from the best shots of [subject], \
                    about [length] long.
                    """)),
            AgentRequestTemplate(
                id: "tutorial", title: String(localized: "Tutorial"), systemImage: "display",
                text: String(localized: """
                    Make a tutorial from the screen recording of [tool], with me in a corner, about [length] long. \
                    Zoom in on [the important steps].
                    """)),
            AgentRequestTemplate(
                id: "captions", title: String(localized: "Captions"), systemImage: "captions.bubble",
                text: String(localized: """
                    Add [Vietnamese / English] captions for the speech, [white with a shadow / bold yellow], \
                    at the [bottom / middle] of the frame.
                    """)),
            AgentRequestTemplate(
                id: "fix", title: String(localized: "Fix a part"), systemImage: "wrench.and.screwdriver",
                text: String(localized: """
                    Fix [the selected clip / the part at mm:ss]: [what is wrong]. I want it to [how it should be].
                    """)),
        ]
    }
}
