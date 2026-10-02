import BashCutProject

extension CommandCatalog {
    /// Clip-level edits that have their own Inspector controls.
    static let clipSpecs: [CommandSpec] = [
        CommandSpec(
            "clip.speed", .edit,
            "Change a clip's constant speed like Inspector › Speed. By default the clip keeps its source and its length "
                + "changes (2× halves it), moving later clips on its layer; with keepDuration it keeps its length and uses "
                + "more or less source. Linked picture and sound change together; a clip is shortened to fit its source.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("speed", .number, "Speed, for example 0.5, 1.5 or 2", required: true,
                                 range: Project.speedRange, cli: .option("speed")),
                CommandParameter("keepDuration", .boolean, "Keep the clip's length instead", default: .bool(false),
                                 cli: .flag("keep-duration")),
                CommandParameter("preservePitch", .boolean, "Keep the voice pitch (on by default)",
                                 cli: .option("preserve-pitch")),
                baseRevision,
            ]),
    ]
}
