import Foundation

/// The 25 brief templates in three groups. Strings are English source keys, translated in Localizable.xcstrings;
/// `{field}` in a pattern is a field ID, kept as is in every language.
public enum BriefCatalog {
    public static let all: [BriefTemplate] = makeTemplates + fixTemplates + finishTemplates

    public static func template(_ id: String) -> BriefTemplate? { all.first { $0.id == id } }

    /// The dock's quick-start cards for a project state, the most likely first (it shows wide).
    public static func quickStarts(for state: BriefFit) -> [BriefTemplate] {
        let ids: [String] = switch state {
        case .none: ["explainer", "news"]
        case .footage: ["vlog", "travel", "food", "montage", "review"]
        case .talk: ["clips", "talk", "silence", "captions", "short"]
        case .timeline: ["hook", "pace", "color", "captions", "publish"]
        case .selection: ["fix", "broll", "color", "mix", "captions"]
        }
        return ids.compactMap(template)
    }

    /// The templates matching `query` by group, the ones that fit `state` first within each group; groups with no
    /// match are left out.
    public static func sections(for state: BriefFit, query: String = "") -> [(group: BriefGroup, templates: [BriefTemplate])] {
        BriefGroup.allCases.compactMap { group in
            let matching = all.filter { $0.group == group && BriefText.matches(query, $0) }
            let sorted = matching.filter { $0.fits(state) } + matching.filter { !$0.fits(state) }
            return sorted.isEmpty ? nil : (group, sorted)
        }
    }

    private static let length = "Length"

    private static let makeTemplates: [BriefTemplate] = [
        BriefTemplate(
            id: "vlog", group: .make, systemImage: "figure.walk", titleKey: "Daily vlog",
            detailKey: "A day, a routine, study with me", recipe: "vlog-daily", fits: [.footage],
            fields: [
                .text("topic", "Topic", "a workday in Saigon"), .chips("length", length, ["30 s", "60 s", "3 min", "8 min"], 1),
                .chips("mood", "Mood", ["chill", "fun", "cinematic"]),
                .chips("words", "Told with", ["voiceover", "captions", "music only"], 1),
            ],
            patternKey: "Make a vlog about {topic}, about {length} long, with a {mood} feel, told with {words}."),
        BriefTemplate(
            id: "travel", group: .make, systemImage: "airplane", titleKey: "Travel",
            detailKey: "Itinerary, costs, places", recipe: "vlog-travel", fits: [.footage],
            fields: [
                .text("place", "Where", "Da Lat, 2 days 1 night"), .chips("length", length, ["30 s", "60 s", "5 min"], 1),
                .chips("frame", "Frame", ["vertical 9:16", "landscape 16:9"]),
                .chips("include", "Include", ["place cards", "total cost", "a map"], 1),
            ],
            patternKey: "Make a travel video about {place}, {length}, {frame}, with {include}."),
        BriefTemplate(
            id: "food", group: .make, systemImage: "fork.knife", titleKey: "Food",
            detailKey: "Dish, place or cooking review", recipe: "vlog-food", fits: [.footage],
            fields: [
                .text("dish", "Dish / place", "beef pho on Hang Trong"), .text("price", "Price", "65k"),
                .chips("length", length, ["30 s", "45 s", "60 s"], 1),
            ],
            patternKey: "Make a review of {dish}, price {price}, {length} long, opening on the bite with the price."),
        BriefTemplate(
            id: "short", group: .make, systemImage: "iphone", titleKey: "Short video",
            detailKey: "2 s hook, big captions", recipe: "vlog-talking-head", fits: [.footage, .talk],
            fields: [
                .text("topic", "Topic"), .chips("length", length, ["15 s", "30 s", "60 s"], 1),
                .chips("platform", "Platform", ["TikTok", "Reels", "Shorts"]),
            ],
            patternKey: """
                Make a {length} vertical video about {topic} for {platform}, with a strong hook in the first 2 seconds \
                and big captions.
                """),
        BriefTemplate(
            id: "talk", group: .make, systemImage: "person.crop.square", titleKey: "Talking to camera",
            detailKey: "Strongest line first, punch-ins", recipe: "vlog-talking-head", fits: [.talk],
            fields: [
                .text("point", "Main point"), .chips("length", length, ["30 s", "60 s", "3 min"], 1),
                .chips("broll", "B-roll", ["yes", "no"]),
            ],
            patternKey: """
                Edit a talking video about {point}, {length}, with the strongest line first and tight cuts; \
                B-roll: {broll}.
                """),
        BriefTemplate(
            id: "clips", group: .make, systemImage: "scissors", titleKey: "Clips from a long video",
            detailKey: "Podcast, livestream, talk → shorts", recipe: "vlog-podcast-clips", fits: [.talk],
            fields: [
                .chips("count", "Number of clips", ["3", "5", "8"], 1), .chips("length", length, ["30 s", "45 s", "60 s"], 1),
                .text("focus", "Focus on"),
            ],
            patternKey: """
                Suggest {count} short clips of {length} from this video, focusing on {focus}; each clip must stand on \
                its own.
                """),
        BriefTemplate(
            id: "review", group: .make, systemImage: "shippingbox", titleKey: "Product review",
            detailKey: "Verdict, 3 points, price", recipe: "vlog-product-review", fits: [.footage],
            fields: [
                .text("product", "Product"), .chips("points", "Points", ["3", "4", "5"]),
                .chips("length", length, ["60 s", "3 min", "8 min"]),
            ],
            patternKey: """
                Edit a review of {product}: open with the verdict, {points} main points with titles, end with the \
                price; under {length}.
                """),
        BriefTemplate(
            id: "ad", group: .make, systemImage: "megaphone", titleKey: "Ad / UGC",
            detailKey: "Hook + CTA, A/B versions", recipe: "vlog-product-ad", fits: [.footage],
            fields: [
                .text("product", "Product"), .text("offer", "Offer"),
                .chips("variants", "Versions", ["1", "2 (A/B hook)", "3"], 1),
            ],
            patternKey: "Make an ad for {product} with {offer} as the call to action, in {variants} versions."),
        BriefTemplate(
            id: "promo", group: .make, systemImage: "bolt", titleKey: "Promo / teaser",
            detailKey: "Beat cuts, kinetic type", recipe: "vlog-promo", fits: [.footage],
            fields: [.text("brand", "Brand"), .chips("length", length, ["15 s", "30 s", "60 s"], 1)],
            patternKey: "Make a {length} promo for {brand}, cut to the beat, with kinetic type."),
        BriefTemplate(
            id: "montage", group: .make, systemImage: "music.note", titleKey: "Music montage",
            detailKey: "Best shots cut on the beat", recipe: "beat-cut", fits: [.footage],
            fields: [.text("music", "Music", "light lo-fi"), .chips("length", length, ["30 s", "60 s", "2 min"], 1)],
            patternKey: "Make a montage cut to the beat of {music} from the best shots, about {length}."),
        BriefTemplate(
            id: "tutorial", group: .make, systemImage: "display", titleKey: "Tutorial",
            detailKey: "Result first, steps, zooms", recipe: "vlog-tutorial", fits: [.footage],
            fields: [
                .text("tool", "Tool"), .chips("presenter", "Presenter in a corner", ["yes", "no"]),
                .chips("length", length, ["60 s", "3 min", "10 min"], 1),
            ],
            patternKey: """
                Make a tutorial for {tool} from the screen recording, presenter in a corner: {presenter}, {length}, \
                zooming in on each click.
                """),
        BriefTemplate(
            id: "explainer", group: .make, systemImage: "lightbulb", titleKey: "Explainer",
            detailKey: "No footage needed: cards, numbers, diagrams", recipe: "vlog-explainer", fits: [.none],
            fields: [
                .text("topic", "Topic", "how an online order moves through the system"),
                .chips("length", length, ["45 s", "90 s", "3 min"]),
                .chips("graphics", "Graphics", ["diagram", "chart", "map", "checklist"]),
                .chips("words", "Told with", ["voiceover", "music only"]),
            ],
            patternKey: """
                Make an explainer about {topic}, {length}, with {words}; main graphic: {graphics}; one block per \
                part, every number sourced.
                """),
        BriefTemplate(
            id: "news", group: .make, systemImage: "newspaper", titleKey: "News",
            detailKey: "From photos, sources, dates", recipe: "vlog-news", fits: [.none],
            fields: [
                .text("story", "News story"),
                .chips("style", "Kind", ["vertical news short", "landscape documentary"]),
            ],
            patternKey: "Make a {style} about {story}, every point with its source and date."),
    ]
}
