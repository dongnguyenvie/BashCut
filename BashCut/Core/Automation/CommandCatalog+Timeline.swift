import BashCutProject
import Foundation

extension CommandCatalog {
    /// Timeline edits, their history and undo (P2-G3: why, evidence, fingerprint, changes).
    static let editSpecs: [CommandSpec] = [
        CommandSpec(
            "timeline.apply", .edit, "Atomically apply validated timeline operations as one undoable edit; "
                + "returns changed false and keeps the revision when nothing changes. why and evidence stay with the "
                + "undo step (timeline.changes lists them). Both the dry run and the apply return fingerprint (the ops "
                + "and baseRev); expectFingerprint refuses an apply whose ops differ from the reviewed dry run.",
            parameters: [
                CommandParameter("ops", .array, "Operations array (CLI: path to ops.json)", required: true,
                                 sensitive: true, cli: .positionalJSONFile),
                baseRevision,
                CommandParameter("label", .string, "Short description of the edit", default: .string("Agent edit"),
                                 cli: .option("label")),
                CommandParameter("dryRun", .boolean,
                                 "Validate without editing; return projected duration, changed IDs, cutsInsideWord "
                                     + "(clip edges the edit leaves inside a transcribed word) and fingerprint",
                                 default: .bool(false), cli: .flag("dry-run")),
                CommandParameter("why", .string, "Why this edit, in one sentence (up to 500 characters)",
                                 cli: .option("why")),
                CommandParameter("evidence", .string,
                                 "What it rests on, separated by ; (review issue IDs, transcript ranges, measurements; "
                                     + "up to 20, 200 characters each)", cli: .option("evidence")),
                CommandParameter("expectFingerprint", .string, "The dry run's fingerprint; refuse other ops",
                                 cli: .option("expect-fingerprint")),
            ]),
        CommandSpec(
            "timeline.changes", .read,
            "Recent edits from the undo history, newest first: step, label, author, why, evidence, at, the rev each "
                + "produced and changes {counts, text, truncated}; undone lists what redo would bring back. Edits made "
                + "before why was recorded have only label and author.",
            parameters: [
                CommandParameter("limit", .integer, "Most edits to list", default: .integer(10), minimum: 1,
                                 maximum: 50, cli: .option("limit")),
                CommandParameter("author", .string, "Only this author (user, claude, codex, …), or agent for any agent",
                                 cli: .option("author")),
            ]),
        CommandSpec("timeline.undo", .edit, "Undo one timeline action.", parameters: [baseRevision]),
        CommandSpec("timeline.redo", .edit, "Redo one timeline action.", parameters: [baseRevision]),
    ]
}
