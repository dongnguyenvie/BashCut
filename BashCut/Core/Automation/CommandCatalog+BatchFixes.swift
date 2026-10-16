import BashCutProject

/// Batch-fix actions (P2-C3): whole-project fixes a pipeline step can run over many existing projects. Applying a
/// brand kit is `library apply <brand>` and re-exporting is the batch `export` step; `BatchStepCatalog` lists them.
extension CommandCatalog {
    static let batchFixSpecs: [CommandSpec] = [
        CommandSpec(
            "captions.replace", .edit,
            "Find and replace in captions. Every caption on the caption layers, as one undoable edit. Case is "
                + "ignored unless matchCase; wholeWord (default true) skips matches inside a longer word. Word timings "
                + "stay when the word count is unchanged, else they are estimated from word length (retimed). No "
                + "match is not an error: replaced 0. Returns rev, replaced (matches), items [{id, before, after, "
                + "count, retimed}]; dryRun returns the same without editing.",
            parameters: [
                CommandParameter("find", .string, "Text to find", required: true, cli: .positional),
                CommandParameter("with", .string, "Replacement text; left out, the matches are removed", cli: .option("with")),
                CommandParameter("matchCase", .boolean, "Match upper and lower case exactly", default: .bool(false),
                                 cli: .flag("match-case")),
                CommandParameter("wholeWord", .boolean, "Only whole words", default: .bool(true),
                                 cli: .option("whole-word")),
                CommandParameter("dryRun", .boolean, "List the changes without editing", default: .bool(false),
                                 cli: .flag("dry-run")),
                baseRevision,
            ]),
        CommandSpec(
            "captions.style", .edit,
            "Restyle every caption on the caption layers as one undoable edit: preset (a library text preset, as "
                + "library apply: its preset, textStyle, brand roles and animation), then style (textStyle fields: "
                + "font, size, fill, stroke, strokeWidth, positionY, align, highlight, uppercase…; null removes one) "
                + "merged over each caption's, then wordStyle (highlight, karaoke, reveal or none). Give at least one. "
                + "Returns rev and items.",
            parameters: [
                CommandParameter("preset", .string, "Library text preset ID, or scope:id", cli: .option("preset")),
                CommandParameter("style", .object, "textStyle fields (CLI: path to style.json)", cli: .positionalJSONFile),
                CommandParameter("wordStyle", .string, "Show words as they are spoken (see captions.words)",
                                 choices: CaptionWords.styles + ["none"], cli: .option("word-style")),
                baseRevision,
            ]),
        CommandSpec(
            "music.replace", .edit,
            "Swap the music bed for a new sound. The clips on the Music layers go and the new sound covers their span (first "
                + "clip's start to last clip's end) on the first clip's layer, so its ducking stays, as one undoable edit, "
                + "with the old level (volumeDb, muted) and fades. Shorter than the span, it repeats back to back unless "
                + "loop is false. Give media (project media ID, such as {media} after a media import step) or library "
                + "(a library audio item, copied into the project's music/ folder). Returns rev, track, removed, items, "
                + "at, duration, looped and shortened.",
            parameters: [
                CommandParameter("media", .string, "Project media ID of the new music", cli: .option("media")),
                CommandParameter("library", .string, "Library audio item ID, or scope:id", cli: .option("library")),
                CommandParameter("from", .number, "Start this many seconds into the new music", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("loop", .boolean, "Repeat the new music to cover the bed (default true)",
                                 default: .bool(true), cli: .option("loop")),
                baseRevision,
            ]),
    ]
}
