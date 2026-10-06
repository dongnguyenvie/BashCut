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
            "What the kind needs (JSON): text-preset {textPreset, text}; sticker {emoji, textPreset} or a file; "
                + "effect-preset {patch: item properties}; transition-preset {kind, duration, easing: linear|in|out|"
                + "inOut, sfx: audio item ID} (or its own sound as file); look {color}",
            cli: .option("params")),
        CommandParameter("file", .string, "File to copy in (audio, image sticker…)", isPath: true, cli: .option("file")),
        CommandParameter("preview", .string, "Preview image, GIF or audio snippet to copy in", isPath: true,
                         cli: .option("preview")),
        CommandParameter("source", .string, "Where it came from (URL or note)", cli: .option("source")),
        CommandParameter("license", .string, "License or terms of use", cli: .option("license")),
    ]

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
                + "scope wait for approval. To improve an existing item, use library update.",
            parameters: [
                CommandParameter("kind", .string, "Item kind", required: true, choices: libraryKinds, cli: .option("kind")),
                CommandParameter("name", .string, "Display name", required: true, cli: .option("name")),
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
                + "item's style, a clip's framing and keyframes, the transition at the selected clip (kind, duration, "
                + "easing and the sound a preset placed there), or a grade.",
            parameters: [
                CommandParameter("kind", .string, "What to save", required: true,
                                 choices: LibrarySelection.kinds.map(\.rawValue), cli: .option("kind")),
                CommandParameter("name", .string, "Display name", required: true, cli: .option("name")),
                CommandParameter("id", .string, "Item ID; from the name by default", cli: .option("id")),
                CommandParameter("item", .string, "Timeline item ID; the selection by default", cli: .option("item")),
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
            "Use a library item on an existing timeline item: a text preset on a text item, an effect preset's "
                + "properties, a look's grade, or a transition preset at the cut beside a video clip (its kind, "
                + "duration and easing, plus its sound on an SFX layer, as one undo step). Defaults to the selected item.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("item", .string, "Timeline item ID; the selection by default", cli: .option("item")),
                baseRevision,
            ]),
        CommandSpec(
            "library.place", .edit,
            "Add a library item to the timeline as a new item: a text preset or emoji sticker as text, a look as an "
                + "adjustment. At the playhead by default.",
            parameters: [
                libraryID, libraryScope,
                CommandParameter("atFrame", .integer, "First timeline frame", minimum: 0, cli: .option("at-frame")),
                CommandParameter("duration", .integer, "Length in timeline frames", minimum: 1, cli: .option("duration")),
                CommandParameter("track", .string, "Layer ID", cli: .option("track")),
                CommandParameter("text", .string, "Text for a text preset instead of its sample", cli: .option("text")),
                baseRevision,
            ]),
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
