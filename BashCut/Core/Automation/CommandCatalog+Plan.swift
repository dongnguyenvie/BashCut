import BashCutProject
import Foundation

/// Planning, gates, selects and quote ranges (P1-D).
extension CommandCatalog {
    /// Credits and the agent's notes on the project: brief, plan and any key (P1-D1, P1-D2).
    static let planSpecs: [CommandSpec] = [
        CommandSpec(
            "project.credits", .read,
            "Rights facts of the media the edit plays (P2-H9): per media {media, name, kind, license and provenance "
                + "as stored, framesOnTop (frames where it is the picture on top)}, frames, and ai {media, "
                + "pictureShare}. Raw facts on request; credit wording and disclosure are yours. Nothing is added to "
                + "the video. With the project's review.credits true, review notes AI picture as info and each "
                + "export's job result carries these facts."),
        CommandSpec(
            "project.data", .read,
            "Read a top-level project field: brief, plan or any key of your own (a free JSON object, the agent's "
                + "notes); null when unset.",
            parameters: [CommandParameter("key", .string, "brief, plan or your own key", required: true, cli: .positional)]),
        CommandSpec(
            "project.set-data", .edit,
            "Set a top-level project field to a JSON object as one undoable edit; with merge, only the given fields "
                + "change (null removes one). Identity, format, "
                + "media and tracks are not data. Core reads only: brief lengthSeconds {min, max} and outputs [names], "
                + "plan sections [{id, label, lengthSeconds {min, max}, frozen}], shots and beats [{id, text, section}] "
                + "when present (directly or under value): review compares them with the edit, as info, and context get "
                + "summarises them so work can resume from them.",
            parameters: [
                CommandParameter("key", .string, "brief, plan or your own key", required: true, cli: .positional),
                CommandParameter("value", .object, "The object (CLI: path to a JSON file)", required: true,
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
                + "is made), G5 draft (before export) and any gate a skill stopped at by name, each ask, notify or skip "
                + "(skip unless the user changed it), and maxReviewRounds. Request each gate with checkpoint request; "
                + "never decide one is approved yourself."),
        CommandSpec(
            "workflow.set-gates", .ui,
            "Change a gate or the review round limit. Agents may only make a gate ask more (skip → notify → ask); "
                + "loosening a gate or changing the round limit is the user's (Settings → Agents → Workflow gates).",
            parameters: [
                CommandParameter("gate", .string, "G1…G5, brief, strategy, roughCut, script, draft or a gate name",
                                 cli: .option("gate")),
                CommandParameter("mode", .string, "Gate mode", choices: ["ask", "notify", "skip"], cli: .option("mode")),
                CommandParameter("maxReviewRounds", .integer, "Review round limit (user only)", minimum: 1, maximum: 10,
                                 cli: .option("max-review-rounds")),
            ]),
        CommandSpec(
            "checkpoint.request", .ui,
            "Stop at a gate: with ask, the user sees the summary and attachments in BashCut and answers approved, "
                + "changes (with a note) or rejected; poll checkpoint status until it is not awaiting_user. With notify the "
                + "user is told and the run goes on; with skip nothing is shown. The answer is bound to the current "
                + "revision and written to the run log; only the user can answer. G2 needs a strategy audit (run append "
                + "audit --point strategy) and, when plan.recipe is set, its skill read: else audit_missing or "
                + "recipe_unread.",
            parameters: [
                CommandParameter("gate", .string, "G1…G5, brief, strategy, roughCut, script, draft, or any name (1–40 "
                                 + "letters, digits, ., -, _) for a stop of your own", required: true,
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
            "Append to the run log: an entry of any kind (start opens a run; stage, skill, audit, round, measured, note "
                + "and end are the usual ones; gate is reserved for checkpoints) with the fields given and any data "
                + "object. The revision, author and time are added. stage: --status done needs --evidence (else it is "
                + "stored unverified), skipped needs --reason; the rough-cut stage while G2 is skip needs what G2 needs. "
                + "skill: a skill you read (stored verified: false unless the kit hook writes it with --verified-by "
                + "hook; skills get records plugin and kit skill reads itself). audit: an auditor's verdict at a point "
                + "(strategy after the story, draft before export, process at the end), bound to the current timeline.",
            parameters: [
                CommandParameter("kind", .string, "Entry kind (1–40 characters; not gate)", required: true, cli: .positional),
                CommandParameter("data", .object, "More fields as a JSON object", cli: .option("data")),
                CommandParameter("stage", .string, "Stage ID (intake, survey, story, rough-cut, rhythm, voiceover, sound, "
                                 + "captions, colour, effects, review, export, learn, or one the plan adds)", cli: .option("stage")),
                CommandParameter("status", .string, "Stage status", choices: WorkflowChecklist.stageStatuses,
                                 cli: .option("status")),
                CommandParameter("evidence", .string, "What proves the stage done, ;-separated (files, job IDs, issue IDs)",
                                 cli: .option("evidence")),
                CommandParameter("reason", .string, "Why the stage was skipped", cli: .option("reason")),
                CommandParameter("name", .string, "Skill read (bc:rough-cut, bashcut.vlog:product-ad)", cli: .option("name")),
                CommandParameter("origin", .string, "Skill origin: kit, plugin, project or user (default from the name)",
                                 choices: ["kit", "plugin", "project", "user"], cli: .option("origin")),
                CommandParameter("verifiedBy", .string, "Set only by the kit's skill hook", choices: ["hook"],
                                 cli: .option("verified-by")),
                CommandParameter("point", .string, "Audit point", choices: WorkflowChecklist.auditPoints, cli: .option("point")),
                CommandParameter("verdict", .string, "Audit verdict", choices: WorkflowChecklist.verdicts, cli: .option("verdict")),
                CommandParameter("findings", .integer, "Audit findings", minimum: 0, maximum: 1_000, cli: .option("findings")),
                CommandParameter("by", .string, "Who audited: a fresh critic or the agent itself (default self)",
                                 choices: WorkflowChecklist.auditors, cli: .option("by")),
                CommandParameter("text", .string, "What happened", cli: .option("text")),
                CommandParameter("round", .integer, "Review round", minimum: 1, maximum: 100, cli: .option("round")),
                CommandParameter("fixed", .integer, "Issues fixed this round", minimum: 0, cli: .option("fixed")),
                CommandParameter("left", .integer, "Issues left", minimum: 0, cli: .option("left")),
                CommandParameter("measured", .string, "Comma-separated checks measured", cli: .option("measured")),
                CommandParameter("notMeasured", .string, "Comma-separated checks not measured", cli: .option("not-measured")),
            ]),
        CommandSpec(
            "run.checklist", .read,
            "The run's checklist, derived from the plan and the run log (never hand-written): stages [{id, skill (the "
                + "plan's stages.<id>.skill, else the kit's), skillRead (recorded by BashCut or the kit hook; "
                + "skillReadUnverified when only you reported it), status pending|started|done|skipped|n/a, required, "
                + "evidence, reason, unverified (done without evidence), by (n/a from the recipe or plan), rules}], "
                + "audits {strategy, draft, process: verdict or null}, auditDetails {verdict, by critic|self, findings, "
                + "rev, current}, recipe {skill, read} and open: what still needs attention; start the hand-off report "
                + "from it."),
    ]

    /// The plan against what was measured (P1-D3).
    static let planCheckSpecs: [CommandSpec] = [
        CommandSpec(
            "review.coverage", .read,
            "Which described source shot each clip plays: per clip on the video layers in time order item, track, "
                + "at/end, media, planShot when the clip has that field, and described {index, start, end and the "
                + "media.describe facts} or null (no description covers it: media describe); counts. Join it with your "
                + "plan yourself; media description lists the shots not played."),
        CommandSpec(
            "script.check", .read,
            "A script against the words heard on the timeline (stored transcripts, else caption words): per beat (the "
                + "beats given, the text as one beat, else the plan's beats) the share of its words heard as written, "
                + "the unmatched words, where it was heard and the section marker it starts in against the beat's "
                + "section; overall similarity and extra heard words.",
            parameters: [
                CommandParameter("beats", .array, "Beats [{id, text, section}] as JSON", cli: .option("beats")),
                CommandParameter("text", .string, "The whole script as one beat", cli: .option("text")),
            ]),
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
            "The project's selects: source ranges {id, media, from, to (seconds), status (free; usually candidate, kept or rejected), quote, "
                + "reason (why it was picked), evidence, mustKeep, order, statusReason (why its status last changed)} and "
                + "counts per status. The user sees and overrides them in the "
                + "Media panel (Selects).",
            parameters: [CommandParameter("status", .string, "Only this status", cli: .option("status"))]),
        CommandSpec(
            "selects.set", .edit,
            "Add, update or remove selects (by id; a new one without id gets one, status candidate) as one undoable "
                + "edit. Give the quote, the reason and the evidence (what was measured) with each; media resolve-range "
                + "gives from/to. On an existing select, status or mustKeep with a reason keeps it as statusReason; "
                + "{id, remove: true} removes it. A must-keep select no clip plays is a review warning.",
            parameters: [
                CommandParameter("value", .array, "Selects (CLI: path to selects.json)", required: true, cli: .positionalJSONFile),
                baseRevision,
            ]),
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
