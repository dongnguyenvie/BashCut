import Foundation

extension BriefCatalog {
    static let fixTemplates: [BriefTemplate] = [
        BriefTemplate(
            id: "fix", group: .fix, systemImage: "wrench.and.screwdriver", titleKey: "Fix the selection",
            detailKey: "Say what is wrong and how it should be", recipe: "edit-workflow", fits: [.selection],
            fields: [
                .chips("part", "Part", ["the selected clip", "the part at the playhead"]),
                .text("problem", "Problem", "the text covers the face"), .text("want", "I want", "move the text up"),
            ],
            patternKey: "Fix {part}: {problem}. I want to {want}."),
        BriefTemplate(
            id: "pace", group: .fix, systemImage: "forward", titleKey: "Faster pace",
            detailKey: "Cut the slack, shorter shots", recipe: "beat-cut", fits: [.timeline],
            fields: [.chips("target", "Target", ["−10 %", "−20 %", "under 60 s"], 1)],
            patternKey: "Make the pace faster, length {target}, keeping the main points."),
        BriefTemplate(
            id: "silence", group: .fix, systemImage: "speaker.slash", titleKey: "Cut silences & filler",
            detailKey: "Um, uh, repeated lines", recipe: "rough-cut", fits: [.talk, .timeline],
            fields: [.chips("level", "Strength", ["light", "medium", "hard"], 1)],
            patternKey: "Cut silences and filler words at a {level} level."),
        BriefTemplate(
            id: "hook", group: .fix, systemImage: "text.quote", titleKey: "Stronger hook",
            detailKey: "3 opening options", recipe: "vlog-hook-script", fits: [.timeline],
            fields: [.chips("options", "Options", ["2", "3"], 1)],
            patternKey: "Write {options} new hooks for the first 2 seconds from real shots, then apply the best one."),
        BriefTemplate(
            id: "broll", group: .fix, systemImage: "film.stack", titleKey: "Add B-roll",
            detailKey: "Illustrate what is being said", recipe: "rough-cut", fits: [.timeline, .talk],
            fields: [.chips("source", "Source", ["my footage", "stock images"])],
            patternKey: "Add B-roll from {source} over the long talking parts."),
        BriefTemplate(
            id: "color", group: .fix, systemImage: "paintpalette", titleKey: "Color grade",
            detailKey: "One look for the whole video", recipe: "color-grade", fits: [.timeline],
            fields: [.chips("look", "Look", ["natural", "warm film", "cinematic", "matte"], 1)],
            patternKey: "Grade the whole video with a {look} look, even across clips."),
        BriefTemplate(
            id: "mix", group: .fix, systemImage: "slider.vertical.3", titleKey: "Balance music & voice",
            detailKey: "Music at one level under the voice", recipe: "audio-mix", fits: [.timeline],
            fields: [.chips("music", "Music", ["keep this music", "find other music"])],
            patternKey: "Balance the sound: background music at one steady level under the voice, no pumping; {music}."),
        BriefTemplate(
            id: "vertical", group: .fix, systemImage: "rectangle.portrait", titleKey: "Vertical 9:16 version",
            detailKey: "Reframed on the subject", recipe: "effects", fits: [.timeline],
            fields: [.chips("captions", "Captions", ["move with it", "keep"])],
            patternKey: "Make a vertical 9:16 version too, reframed on the subject; captions: {captions}."),
    ]

    static let finishTemplates: [BriefTemplate] = [
        BriefTemplate(
            id: "captions", group: .finish, systemImage: "captions.bubble", titleKey: "Captions",
            detailKey: "From speech, with a style", recipe: "captions-text", fits: [.timeline, .talk],
            fields: [
                .chips("language", "Language", ["Vietnamese", "English"]),
                .chips("style", "Style", ["white with outline", "bold yellow", "word by word"], 2),
                .chips("position", "Position", ["bottom", "middle"]),
            ],
            patternKey: "Add {language} captions, {style}, at the {position} of the frame."),
        BriefTemplate(
            id: "translate", group: .finish, systemImage: "globe", titleKey: "Translate captions",
            detailKey: "Add a caption track in another language", recipe: "captions-text", fits: [.timeline],
            fields: [.chips("target", "Into", ["English", "Vietnamese", "Japanese"])],
            patternKey: "Translate the captions into {target}, keeping the timing."),
        BriefTemplate(
            id: "cover", group: .finish, systemImage: "photo", titleKey: "Cover image",
            detailKey: "3 options, checked at phone size", recipe: "vlog-publish", fits: [.timeline],
            fields: [.text("text", "Cover text")],
            patternKey: "Suggest 3 cover images with the text: {text}."),
        BriefTemplate(
            id: "publish", group: .finish, systemImage: "paperplane", titleKey: "Export & post",
            detailKey: "Per platform, caption, hashtags", recipe: "vlog-publish", fits: [.timeline],
            fields: [.chips("platform", "Platform", ["TikTok", "Reels", "YouTube", "all of them"], 3)],
            patternKey: "Export for {platform}, with a title, caption, hashtags and YouTube chapters where they apply."),
    ]
}
