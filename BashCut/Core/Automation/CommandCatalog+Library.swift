import BashCutProject

extension CommandCatalog {
    private static let libraryKinds = LibraryKind.allCases.map(\.rawValue)
    private static let libraryKind = CommandParameter(
        "kind", .string, "Item kind", choices: libraryKinds, cli: .option("kind"))
    private static let libraryPanel = CommandParameter(
        "panel", .string, "Only items the library panel shows", choices: libraryPanels.filter { $0 != "media" },
        cli: .option("panel"))
    private static let libraryID = CommandParameter(
        "id", .string, "Item ID, or scope:id to pick one scope", required: true, cli: .positional)
    private static let libraryScope = CommandParameter(
        "scope", .string, "Look only in this scope; without it project, user, plugin, then built-in",
        choices: LibraryScope.allCases.map(\.rawValue), cli: .option("scope"))
    private static let writableScope = CommandParameter(
        "scope", .string,
        "project (the open project's .bashcut/library; the default) or user (this Mac; agents need approval)",
        default: .string("project"), choices: ["project", "user"], cli: .option("scope"))
    private static let itemFields: [CommandParameter] = [
        CommandParameter("tags", .string, "Comma-separated tags (mood, use, genre…)", cli: .option("tags")),
        CommandParameter("pack", .string, "Pack or collection name the panel groups it under", cli: .option("pack")),
        CommandParameter(
            "params", .object,
            "What the kind needs (JSON): text-preset {textPreset, text, textStyle: {size, positionY, strokeWidth} (the "
                + "item property ranges), animation: a clip motion preset}, the last two optional; sticker {emoji, textPreset} or a file (PNG, "
                + "JPEG, HEIC, WebP, GIF, APNG, or a .mov/.mp4 with alpha; not Lottie) with {stickerKind: "
                + "emoji|image|animated|video-alpha (from the file by default), size: width as 0.01–1 of the frame, "
                + "position: center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right or {x, y} in 0–1, "
                + "animation: a clip motion preset, seconds}, all optional; "
                + "effect-preset (a recipe) {steps: [{op: motion|keyframes|speed|speedCurve|reverse|freeze|patch|sfx|text, "
                + "…}], parameters: {name: {default, min, max}}} or the older {patch: item properties}, with its own sound "
                + "as file; transition-preset {kind, duration, easing: linear|in|out|"
                + "inOut, sfx: audio item ID} (or its own sound as file); look (a filter stack) {color: {exposure, contrast, "
                + "saturation, lutStrength}, lutName} with an optional .cube LUT as file; audio (its file required) {role: "
                + "music|sfx|ambience, seconds, bpm, loopable, lufs, truePeak}, all optional (library add measures seconds "
                + "and picks a role by length; library analyze fills the rest), with mood and genre as tags",
            cli: .option("params")),
        CommandParameter(
            "file", .string, "File to copy in (audio, image or alpha-movie sticker, a look's .cube LUT…)", isPath: true,
            cli: .option("file")),
        CommandParameter("preview", .string, "Preview image, GIF or audio snippet to copy in", isPath: true,
                         cli: .option("preview")),
        CommandParameter("source", .string, "Where it came from (URL or note)", cli: .option("source")),
        CommandParameter("license", .string, "License or terms of use", cli: .option("license")),
    ]

    /// The provider, count and saving options of library search and library generate (#81).
    private static func libraryProviderParameters(limit: Int) -> [CommandParameter] {
        [
            CommandParameter(
                "provider", .string, "Plugin or provider ID; the first available provider that serves the kind by default",
                cli: .option("provider")),
            CommandParameter("limit", .integer, "Most candidates to return", default: .integer(limit), minimum: 1,
                             maximum: 50, cli: .option("limit")),
            CommandParameter(
                "save", .integer, "Also save the candidate with this index (from 0) when the job finishes", minimum: 0,
                cli: .option("save")),
            CommandParameter(
                "scope", .string, "Where save puts it: project (the default) or user (agents need approval)",
                default: .string("project"), choices: ["project", "user"], cli: .option("scope")),
        ]
    }

    /// The library panels' items (#74): list, save, improve, remove, use, packs and usage.
    static let librarySpecs: [CommandSpec] = [
        CommandSpec(
            "library.list", .read,
            "List library items (Audio, Text, Stickers, Effects, Transitions, Filters, Voice) from the open project, "
                + "this Mac, plugins and built-in packs, with usage. Check here before making something new.",
            parameters: [
                libraryKind, libraryPanel,
                CommandParameter("tag", .string, "Only items with this tag", cli: .option("tag")),
                libraryScope,
                CommandParameter("createdBy", .string, "Only items made by", choices: ["user", "agent", "plugin", "built-in"],
                                 cli: .option("created-by")),
                CommandParameter("pack", .string, "Only items in this pack", cli: .option("pack")),
                CommandParameter("query", .string, "Text to find in the id, name, pack or tags", cli: .option("query")),
            ]),
        CommandSpec(
            "library.get", .read, "Read one library item, with its earlier versions and file paths.",
            parameters: [libraryID, libraryScope]),
        CommandSpec(
            "library.stats", .read,
            "Usage of every library item, the saved items nobody used, and groups of duplicates (same kind and "
                + "content), to find what to prune or merge.",
            parameters: [libraryKind, libraryPanel]),
        CommandSpec(
            "library.add", .edit,
            "Save a new library item in the project or on this Mac. Files are copied in. Agents saving to the user "
                + "scope wait for approval. To improve an existing item, use library update. fromResult saves a "
                + "candidate of a finished library search or library generate job instead (its kind, name, files, "
                + "source and license; the other fields here override them).",
            parameters: [
                CommandParameter("kind", .string, "Item kind (required unless fromResult)", choices: libraryKinds,
                                 cli: .option("kind")),
                CommandParameter("name", .string, "Display name (required unless fromResult)", cli: .option("name")),
                CommandParameter(
                    "fromResult", .string,
                    "A library search or generate candidate as <job>:<index> (index from 0, as the job result lists it)",
                    cli: .option("from-result")),
                CommandParameter("id", .string, "Item ID: lowercase letters, digits and hyphens; from the name by default",
                                 cli: .option("id")),
                writableScope,
            ] + itemFields),
        CommandSpec(
            "library.update", .edit,
            "Improve a library item: saves a new version (the old one stays in its history). Built-in and plugin "
                + "items are read-only, so pass as to save an improved copy under a new ID instead.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("name", .string, "New display name", cli: .option("name")),
            ] + itemFields + [
                CommandParameter("as", .string, "Save a copy under this new ID instead of a new version", cli: .option("as")),
                CommandParameter("into", .string, "Scope of the copy (with as); project by default",
                                 choices: ["project", "user"], cli: .option("into")),
            ]),
        CommandSpec(
            "library.remove", .edit,
            "Remove a project or user library item and its files. Built-in and plugin items cannot be removed. "
                + "Agents removing from the user scope wait for approval.",
            parameters: [libraryID, libraryScope]),
        CommandSpec(
            "library.save-selection", .edit,
            "Save what is selected on the timeline as a new library item (the panels' Save selection as…): a text "
                + "item's preset, text, textStyle (size, position, outline) and motion preset when its keyframes are one, "
                + "a clip's effect as a recipe (reverse, speed or speed ramp, framing, keyframes scaled to the "
                + "clip's length, and the sound effect at its start; a still of the clip as its preview), the transition "
                + "at the selected clip (kind, duration, easing and the sound a preset placed there), or a grade as a look: "
                + "the full filter stack, with the project LUT it uses copied in as the look's file, or an audio clip (or "
                + "project audio media) as an audio item: its file copied in, its length, and music or sfx from its layer, or "
                + "an overlay item as a sticker: an image or alpha movie with its file, size, position and length, or an "
                + "emoji text item with its text preset.",
            parameters: [
                CommandParameter("kind", .string, "What to save", required: true,
                                 choices: LibrarySelection.kinds.map(\.rawValue), cli: .option("kind")),
                CommandParameter("name", .string, "Display name", required: true, cli: .option("name")),
                CommandParameter("id", .string, "Item ID; from the name by default", cli: .option("id")),
                CommandParameter("item", .string, "Timeline item ID; the selection by default", cli: .option("item")),
                CommandParameter("media", .string, "Audio: project audio media ID instead of a timeline clip",
                                 cli: .option("media")),
                writableScope,
                itemFields[0], itemFields[1],
            ]),
        CommandSpec(
            "library.move", .edit,
            "Move a saved item between the project and this Mac, with its versions, files and use count. Agents "
                + "moving into or out of the user scope wait for approval.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("to", .string, "Destination", required: true, choices: ["project", "user"],
                                 cli: .option("to")),
            ]),
        CommandSpec(
            "library.apply", .edit,
            "Use a library item on an existing timeline item: a text preset on a text item (its preset, then its stored "
                + "textStyle over the item's and its animation, as one undo step), an effect preset's "
                + "recipe on a clip (every step, its sounds and text, and a split for a from/to range, as one undo step; set "
                + "overrides its parameters; when a reverse step needs a new reversed copy it runs as a job), a look's grade "
                + "(adding its LUT to the project when it has one, in the same undo step), or a transition preset at the cut "
                + "beside a video clip (its kind, duration and easing, plus its sound on an SFX layer, as one undo step). "
                + "Defaults to the selected item.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("item", .string, "Timeline item ID; the selection by default", cli: .option("item")),
                CommandParameter(
                    "set", .string, "Effect preset parameters: name=value pairs (strength=1.5,frames=12) or a JSON object",
                    cli: .option("set")),
                CommandParameter("from", .integer, "Effect preset: first timeline frame of the part of the clip to change",
                                 minimum: 0, cli: .option("from")),
                CommandParameter("to", .integer, "Effect preset: timeline frame after that part (the clip's end by default)",
                                 minimum: 1, cli: .option("to")),
                baseRevision,
            ]),
        CommandSpec(
            "library.place", .edit,
            "Add a library item to the timeline as a new item: a text preset (with its stored textStyle and animation) "
                + "or emoji sticker as text, an image, "
                + "animated or video-alpha sticker (its file copied into the project's stickers/ folder once per content, "
                + "imported and placed on the Overlay layer, added when missing, at size and position, as one undo step; "
                + "an animated sticker shows its first frame for now and the result says so), a look as an "
                + "adjustment (with its LUT added to the project in the same undo step), or audio: its file copied into the "
                + "project's music/ or sfx/ folder (once per content), imported and placed on the Music layer (music, "
                + "ambience) or SFX layer (sfx), the layer added when missing, as one undo step. duration trims a sound; "
                + "longer than the file, a loopable sound repeats back to back and another plays once (the result says so). "
                + "At the playhead by default.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("atFrame", .integer, "First timeline frame", minimum: 0, cli: .option("at-frame")),
                CommandParameter("duration", .integer, "Length in timeline frames", minimum: 1, cli: .option("duration")),
                CommandParameter("track", .string, "Layer ID; for audio, the Music or SFX layer by its role by default; "
                                 + "for a sticker, the Overlay layer", cli: .option("track")),
                CommandParameter(
                    "position", .string,
                    "Sticker: center, top, bottom, left, right, top-left, top-right, bottom-left or bottom-right (inside "
                        + "the safe area), or x,y in 0–1 (its centre, from the top left); the sticker's default otherwise",
                    cli: .option("position")),
                CommandParameter("size", .number, "Sticker: width as a fraction of the frame width (0.3 by default)",
                                 range: 0.01...1, cli: .option("size")),
                CommandParameter("text", .string, "Text for a text preset instead of its sample", cli: .option("text")),
                baseRevision,
            ]),
        CommandSpec(
            "library.analyze", .edit,
            "Measure an audio library item's file and save the values as a new version: its length, integrated "
                + "loudness and true peak (an audio.loudness provider, as audio measure) and, unless it is a sound effect, "
                + "its tempo in BPM (an audio.beats provider, as beats detect). Runs as a job; a missing provider leaves "
                + "that value and says why in notes. Agents saving to the user scope wait for approval. Tag mood and "
                + "genre with library update --tags after listening or reading the analysis.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("provider", .string, "audio.loudness provider ID; the project's choice by default",
                                 cli: .option("provider")),
            ],
            execution: .job),
        CommandSpec(
            "library.preview", .ui,
            "Play a library item's sound in BashCut (the Audio panel's play button), stopping any other; stop, or no "
                + "id, stops it.",
            parameters: [
                CommandParameter("id", .string, "Item ID, or scope:id", cli: .positional),
                libraryScope,
                CommandParameter("stop", .boolean, "Stop the sound playing", default: .bool(false), cli: .flag("stop")),
            ]),
        CommandSpec(
            "library.search", .edit,
            "Ask an installed plugin that provides library.search (sounds, stickers, GIFs… from Freesound, Giphy or "
                + "another source) for candidate items of a kind. Runs as a job; its result lists candidates with their "
                + "fields, downloaded file and preview paths, source and license. Nothing is saved until library add "
                + "--from-result <job>:<index> (or save here) copies one into the library. Network use is the plugin's.",
            parameters: [
                CommandParameter("query", .string, "What to look for", required: true, cli: .positional),
                CommandParameter("kind", .string, "Item kind", required: true, choices: libraryKinds, cli: .option("kind")),
            ] + libraryProviderParameters(limit: 12) + [
                CommandParameter("page", .integer, "Result page, from 1", default: .integer(1), minimum: 1, maximum: 1_000,
                                 cli: .option("page")),
            ],
            execution: .job),
        CommandSpec(
            "library.generate", .edit,
            "Ask an installed plugin that provides library.generate (AI music, stickers…) to make candidate items of a "
                + "kind from a prompt. Runs as a job; its result lists candidates like library search. Nothing is saved "
                + "until library add --from-result <job>:<index> (or save here) copies one into the library.",
            parameters: [
                CommandParameter("prompt", .string, "What to make", required: true, sensitive: true, cli: .positional),
                CommandParameter("kind", .string, "Item kind", required: true, choices: libraryKinds, cli: .option("kind")),
            ] + libraryProviderParameters(limit: 4) + [
                CommandParameter("params", .object, "Hints for the provider (JSON), such as {\"seconds\": 30}",
                                 cli: .option("params")),
            ],
            execution: .job),
        CommandSpec(
            "library.import-pack", .edit,
            "Add a pack (a folder with pack.json and files, or a .zip of one) to the project or user library. IDs "
                + "already there are refused unless replace saves them as new versions.",
            parameters: [
                CommandParameter("path", .string, "Pack folder or .zip", required: true, isPath: true, cli: .positional),
                writableScope,
                CommandParameter("replace", .boolean, "Save items whose ID exists as new versions", default: .bool(false),
                                 cli: .flag("replace")),
            ]),
        CommandSpec(
            "library.export-pack", .edit,
            "Write library items as a pack folder (pack.json and files) to share or import elsewhere: one pack, or "
                + "every item of a kind or scope.",
            parameters: [
                CommandParameter("output", .string, "New or empty folder to write", required: true, isPath: true,
                                 cli: .option("output")),
                CommandParameter("pack", .string, "Items in this pack", cli: .option("pack")),
                libraryKind, libraryScope,
                CommandParameter("name", .string, "Pack name; the pack filter or the folder name by default",
                                 cli: .option("name")),
            ]),
    ]
}
