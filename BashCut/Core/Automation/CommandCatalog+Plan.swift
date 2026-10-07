import BashCutProject
import Foundation

/// Planning, gates, selects and quote ranges (P1-D).
extension CommandCatalog {
    /// The brief and the edit plan (P1-D1, P1-D2).
    static let planSpecs: [CommandSpec] = [
        CommandSpec(
            "project.brief", .read,
            "Read the project brief: goal, audience, outputs, angle, lengthSeconds, notes as {value, status stated|"
                + "inferred|confirmed, source?}, and ideas and references. Null when none."),
        CommandSpec(
            "project.set-brief", .edit,
            "Set the brief as one undoable edit (validated: fields {value, status, source?}, ideas and references up to "
                + "100 objects); with merge, only the given fields change (null removes one). Review compares its "
                + "length and outputs with the edit, as info.",
            parameters: [
                CommandParameter("value", .object, "The brief (CLI: path to brief.json)", required: true,
                                 cli: .positionalJSONFile),
                CommandParameter("merge", .boolean, "Change only the given fields", cli: .flag("merge")),
                baseRevision,
            ]),
        CommandSpec(
            "plan.get", .read,
            "Read the edit plan: mode (create, directed, revision), stage, options, sections [{id, label, "
                + "lengthSeconds {min, max}, reason, frozen}], shots [{id, section, purpose, size, move, mustShow, "
                + "targetSeconds, source footage|stock|generated}], beats [{id, section, text}], decisions, ranges "
                + "(the review profile values chosen, {min, max, source, reason}) and notes. Null when none."),
        CommandSpec(
            "plan.set", .edit,
            "Set the edit plan as one undoable edit (validated shape); with merge, only the given top-level fields "
                + "change (null removes one). Review compares each section's planned length with its section "
                + "marker, as info. context get summarises it so work can resume from it.",
            parameters: [
                CommandParameter("value", .object, "The plan (CLI: path to plan.json)", required: true,
                                 cli: .positionalJSONFile),
                CommandParameter("merge", .boolean, "Change only the given fields", cli: .flag("merge")),
                baseRevision,
            ]),
    ]

    /// Workflow gates, checkpoints and the run log (P1-D4–D6).
    static let workflowSpecs: [CommandSpec] = [
        CommandSpec(
            "workflow.gates", .read,
            "The user's workflow gates: G1 brief, G2 strategy, G3 roughCut (rough-cut sheet), G4 script (before speech "
                + "is made), G5 draft (before export), each ask, notify or skip (ask unless the user changed it), and "
                + "maxReviewRounds. Request each gate with checkpoint request; never decide one is approved yourself."),
        CommandSpec(
            "workflow.set-gates", .ui,
            "Change a gate or the review round limit. Agents may only make a gate ask more (skip → notify → ask); "
                + "loosening a gate or changing the round limit is the user's (Settings → Agents → Workflow gates).",
            parameters: [
                CommandParameter("gate", .string, "G1…G5 or brief, strategy, roughCut, script, draft", cli: .option("gate")),
                CommandParameter("mode", .string, "Gate mode", choices: ["ask", "notify", "skip"], cli: .option("mode")),
                CommandParameter("maxReviewRounds", .integer, "Review round limit (user only)", minimum: 1, maximum: 10,
                                 cli: .option("max-review-rounds")),
            ]),
        CommandSpec(
            "checkpoint.request", .ui,
            "Stop at a gate: with ask, the user sees the summary and attachments in BashCut and answers approved, "
                + "changes (with a note) or rejected; poll checkpoint status until it is not awaiting_user. With notify the "
                + "user is told and the run goes on; with skip nothing is shown. The answer is bound to the current "
                + "revision and written to the run log; only the user can answer.",
            parameters: [
                CommandParameter("gate", .string, "G1…G5 or brief, strategy, roughCut, script, draft", required: true,
                                 cli: .positional),
                CommandParameter("summary", .string, "What the user is asked to approve", required: true, cli: .option("summary")),
                CommandParameter("attach", .string, "Comma-separated files to show (sheets, stills); relative to the project",
                                 cli: .option("attach")),
            ]),
        CommandSpec(
            "checkpoint.status", .read,
            "A checkpoint of this session (default the last): status awaiting_user, approved, changes, rejected, skipped, "
                + "notified or withdrawn, the user's note, the revision it covers and stale when the project has changed since.",
            parameters: [CommandParameter("id", .string, "Checkpoint ID", cli: .positional)]),
        CommandSpec(
            "run.log", .read,
            "The run log (.bashcut/run-log.jsonl, append-only): starts, stages, gates with the user's answers, review "
                + "rounds (fixed, left), what was measured and not measured, notes. Read it for the hand-off report and "
                + "self-learn instead of the chat.",
            parameters: [
                CommandParameter("run", .string, "current (default), all or a run number", cli: .option("run")),
                CommandParameter("kind", .string, "Only this kind", cli: .option("kind")),
                CommandParameter("limit", .integer, "Last N entries", minimum: 1, maximum: 10_000, cli: .option("limit")),
            ]),
        CommandSpec(
            "run.append", .ui,
            "Append to the run log: start (opens a run), stage, round, measured, note or end. Gate entries come only from "
                + "checkpoints. The revision, author and time are added.",
            parameters: [
                CommandParameter("kind", .string, "Entry kind", required: true, choices: ["start", "stage", "round", "measured", "note", "end"],
                                 cli: .positional),
                CommandParameter("stage", .string, "Stage name", cli: .option("stage")),
                CommandParameter("text", .string, "What happened", cli: .option("text")),
                CommandParameter("round", .integer, "Review round", minimum: 1, maximum: 100, cli: .option("round")),
                CommandParameter("fixed", .integer, "Issues fixed this round", minimum: 0, cli: .option("fixed")),
                CommandParameter("left", .integer, "Issues left", minimum: 0, cli: .option("left")),
                CommandParameter("measured", .string, "Comma-separated checks measured", cli: .option("measured")),
                CommandParameter("notMeasured", .string, "Comma-separated checks not measured", cli: .option("not-measured")),
            ]),
    ]

    /// The plan against what was measured (P1-D3).
    static let planCheckSpecs: [CommandSpec] = [
        CommandSpec(
            "review.coverage", .read,
            "The plan's shot rows against the footage: per planned shot the described shots that fit it (size, and every "
                + "mustShow name among the described subjects), the clips that place it (a clip's planShot field, or the "
                + "described shot it plays fits), and a status placed, found, missing or undescribed (no media described "
                + "yet: media describe). Facts only; what is enough is the plan's."),
        CommandSpec(
            "script.check", .read,
            "The plan's script beats against the words heard on the timeline (stored transcripts, else caption words): "
                + "per beat the share of its words heard as written, the unmatched words, where it was heard and the "
                + "section marker it starts in against the planned section; overall similarity and extra heard words."),
    ]

    /// Select by quote (P1-D7).
    static let quoteSpecs: [CommandSpec] = [
        CommandSpec(
            "media.resolve-range", .read,
            "A source range from what was said, in the media's stored transcript: a quote (the place its words match "
                + "best; equal places listed in alternatives, in order, never ranked), word indices FIRST-LAST, or rough "
                + "from/to seconds snapped outwards to the words they cut into (snap gives how far each edge moved). "
                + "A quote's matched is the share of its words heard in place: under 1 the transcript differs (a "
                + "misheard word, or a quote that is not there), so read text before using the range. "
                + "Returns from/to seconds and in/out frames for media place, the text, and per edge midWord, "
                + "midSentence (inside a transcript phrase) and the nearest word and sentence edges before and after.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .positional),
                CommandParameter("quote", .string, "Words as said", cli: .option("quote")),
                CommandParameter("words", .string, "Word indices FIRST-LAST", cli: .option("words")),
                CommandParameter("from", .number, "Rough start, seconds", range: 0...86_400, cli: .option("from")),
                CommandParameter("to", .number, "Rough end, seconds", range: 0...86_400, cli: .option("to")),
            ]),
        CommandSpec(
            "captions.find", .read,
            "Where words are said on the timeline: every place the text's words come in order (stored transcripts "
                + "heard through the clips, else caption words), with at/end frames.",
            parameters: [CommandParameter("text", .string, "Words to find", required: true, cli: .positional)]),
    ]

    /// The selects store (P1-D8).
    static let selectsSpecs: [CommandSpec] = [
        CommandSpec(
            "selects.list", .read,
            "The project's selects: source ranges {id, media, from, to (seconds), status candidate|kept|rejected, quote, "
                + "reason (why it was picked), evidence, mustKeep, order, statusReason (why its status last changed)} and "
                + "counts per status. The user sees and overrides them in the "
                + "Media panel (Selects).",
            parameters: [CommandParameter("status", .string, "Only this status", choices: ProjectSelect.statuses, cli: .option("status"))]),
        CommandSpec(
            "selects.set", .edit,
            "Add or update selects (by id; a new one without id gets one, status candidate) as one undoable edit. Give "
                + "the quote, the reason and the evidence (what was measured) with each; media resolve-range gives from/to.",
            parameters: [
                CommandParameter("value", .array, "Selects (CLI: path to selects.json)", required: true, cli: .positionalJSONFile),
                baseRevision,
            ]),
        CommandSpec(
            "selects.mark", .edit,
            "Change the status or mustKeep of selects (comma-separated IDs), with an optional reason (kept as statusReason; "
                + "the pick's reason stays), as one edit. A "
                + "must-keep select no clip plays is a review warning.",
            parameters: [
                CommandParameter("ids", .string, "Select IDs", required: true, cli: .positional),
                CommandParameter("status", .string, "New status", choices: ProjectSelect.statuses, cli: .option("status")),
                CommandParameter("mustKeep", .boolean, "Must the edit keep it", cli: .option("must-keep")),
                CommandParameter("reason", .string, "Why", cli: .option("reason")),
                baseRevision,
            ]),
        CommandSpec(
            "selects.remove", .edit, "Remove selects (comma-separated IDs) as one edit.",
            parameters: [CommandParameter("ids", .string, "Select IDs", required: true, cli: .positional), baseRevision]),
        CommandSpec(
            "selects.place", .edit,
            "Lay the kept selects (or the given IDs) in order (order, else source start), from atFrame or the first "
                + "one's layer end, as one undoable edit: pictures on Main, sound-only media on the dialogue layer (else "
                + "music); returns the new item IDs.",
            parameters: [
                CommandParameter("ids", .string, "Select IDs instead of the kept ones", cli: .option("ids")),
                CommandParameter("atFrame", .integer, "Timeline frame", minimum: 0, cli: .option("at-frame")),
                baseRevision,
            ]),
    ]

    /// Derived projects and variants (P1-D9).
    static let variantSpecs: [CommandSpec] = [
        CommandSpec(
            "project.derive", .edit,
            "Write a sibling project per select (the kept ones, or ids): same canvas, outputs, review profile, brief and "
                + "layers, only that media (paths made absolute) and the select's range on Main, with derivedFrom. "
                + "Several shorts from one long recording; the open project does not change and nothing opens.",
            parameters: [
                CommandParameter("ids", .string, "Select IDs instead of the kept ones", cli: .option("ids")),
                CommandParameter("directory", .string, "Parent folder; defaults to the one holding this project's folder",
                                 isPath: true, cli: .option("dir")),
            ]),
        CommandSpec(
            "variants.create", .edit,
            "Write a full copy of the project next to it as a variant that records what it changes (one thing per "
                + "variant), for example an ad with another hook. Open it to make the change; diff compares them.",
            parameters: [
                CommandParameter("name", .string, "Short name (folder and title suffix)", required: true, cli: .positional),
                CommandParameter("changed", .string, "What this variant changes", required: true, cli: .option("changed")),
                CommandParameter("directory", .string, "Parent folder", isPath: true, cli: .option("dir")),
            ]),
        CommandSpec(
            "variants.list", .read, "The variants and derived projects of this project in the sibling folders, with what each changes.",
            parameters: [CommandParameter("directory", .string, "Parent folder", isPath: true, cli: .option("dir"))]),
        CommandSpec(
            "variants.diff", .read,
            "What differs between two projects (default: this one against other): top-level fields, items added, "
                + "removed or changed, durations and each one's recorded change.",
            parameters: [
                CommandParameter("other", .string, "Project file or folder", required: true, isPath: true, cli: .positional),
                CommandParameter("base", .string, "Project file or folder instead of the open one", isPath: true, cli: .option("base")),
            ]),
    ]

    /// Covers, chapters and captions per output (P1-F3, P1-F4).
    static let packagingSpecs: [CommandSpec] = [
        CommandSpec(
            "export.cover", .ui,
            "Write a still of the composed frame for each cover aspect into render/: the asked aspects (W:H, comma "
                + "separated), else each output's cover aspect from platforms get (cover.aspect, else its shape), cropped "
                + "from the centre. Pick the frame from real frames (timeline sheet); look at the result.",
            parameters: [
                CommandParameter("frame", .integer, "Timeline frame", required: true, minimum: 0, cli: .positional),
                CommandParameter("aspect", .string, "Aspects such as 16:9,9:16", cli: .option("aspect")),
                CommandParameter("size", .integer, "Long edge in pixels", minimum: 160, maximum: 3_840, cli: .option("size")),
            ]),
        CommandSpec(
            "export.chapters", .ui,
            "A chapter list from the section markers (00:00 first; an Intro at 0 when no marker is there) and each "
                + "rule of the platform's chapter fact (first at 00:00, the least count, the shortest chapter) with "
                + "whether it holds. With write, saves render/chapters-<platform>.txt. Caption mode per output is "
                + "output.captions (preset → {mode burn|sidecar|both|none, format srt|vtt, track}); the export follows it.",
            parameters: [
                CommandParameter("platform", .string, "Platform whose rule applies (default youtube)", cli: .option("platform")),
                CommandParameter("write", .boolean, "Save the list in render/", cli: .flag("write")),
            ]),
    ]
}
