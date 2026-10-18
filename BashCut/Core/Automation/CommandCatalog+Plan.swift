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
                + "summarises them so work can resume from them. Returns {key, bytes, keys, rev}; --echo returns the "
                + "stored value too.",
            parameters: [
                CommandParameter("key", .string, "brief, plan or your own key", required: true, cli: .positional),
                CommandParameter("value", .object, "The object (CLI: path to a JSON file)", required: true,
                                 cli: .positionalJSONFile),
                CommandParameter(
                    "merge", .boolean, "Merge into the stored value: objects key by key (null deletes), arrays and values replace",
                    cli: .flag("merge")),
                CommandParameter("echo", .boolean, "Return the stored value as well", cli: .flag("echo")),
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
                + "recipe_unread. G5 by an agent needs every stage the plan marks required before review done or "
                + "skipped with a reason: else stage_pending (data.stages).",
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
                + "notified or withdrawn, the user's note, the revision it covers and stale when the project has changed since. "
                + "With wait, the call returns as soon as the user answers, or after that many seconds: wait instead of polling.",
            parameters: [
                CommandParameter("id", .string, "Checkpoint ID", cli: .positional),
                CommandParameter("wait", .integer, "Seconds to wait for the user's answer", minimum: 1,
                                 maximum: JobWaitDefaults.maximum, cli: .option("wait")),
            ]),
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
                + "stored unverified), skipped needs --reason; marking the rough-cut stage done while G2 is skip needs what "
                + "G2 needs (progress reports are never gated); marking review done needs every stage the plan marks "
                + "required before review done or skipped: else stage_pending. "
                + "skill: a skill you read (stored verified: false unless the kit hook writes it with --verified-by "
                + "hook; skills get records plugin and kit skill reads itself). audit: an auditor's verdict at a point "
                + "(strategy after the story, draft before export, process at the end), bound to the current timeline. "
                + "BashCut writes these stages itself (auto: true): rough-cut and captions on plan apply, review on a "
                + "review run that passes while no required stage is open, export when an export lands. The run panel the user watches shows the "
                + "latest stage entry as the current stage (status started, the default) with its text, progress and "
                + "eta: one short call as each stage starts, such as run append stage --stage cut --text \"Cutting 12 "
                + "shots\" --eta 120 (cut, color and audio mean rough-cut, colour and sound).",
            parameters: [
                CommandParameter("kind", .string, "Entry kind (1–40 characters; not gate)", required: true, cli: .positional),
                CommandParameter("data", .object, "More fields as a JSON object", cli: .option("data")),
                CommandParameter("stage", .string, "Stage ID (intake, survey, story, rough-cut, rhythm, voiceover, sound, "
                                 + "captions, colour, effects, review, export, learn, or one the plan adds; cut and "
                                 + "color work too)", cli: .option("stage")),
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
                CommandParameter("text", .string, "What happened; for a stage, the step the run panel shows", cli: .option("text")),
                CommandParameter("progress", .number, "Stage started: how far it is, 0–1", range: 0...1, cli: .option("progress")),
                CommandParameter("eta", .integer, "Stage started: seconds it still needs, your estimate", minimum: 0,
                                 maximum: 86_400, cli: .option("eta")),
                CommandParameter("round", .integer, "Review round", minimum: 1, maximum: 100, cli: .option("round")),
                CommandParameter("fixed", .integer, "Issues fixed this round", minimum: 0, cli: .option("fixed")),
                CommandParameter("left", .integer, "Issues left", minimum: 0, cli: .option("left")),
                CommandParameter("measured", .string, "Comma-separated checks measured", cli: .option("measured")),
                CommandParameter("notMeasured", .string, "Comma-separated checks not measured", cli: .option("not-measured")),
            ]),
        CommandSpec(
            "run.status", .read,
            "What the run panel shows: progress {run, startedAt, elapsed, current, text, progress, remaining (the ETA "
                + "counted down), stageElapsed, finished, exportedAt, stages [{id, status pending|active|started|done|"
                + "skipped, seconds, text}]} from the run log, and once the run exported result {path, duration, cuts, "
                + "lufs, truePeakDbTP, loudnessVerified, review {errors, warnings, accepted} on the current timeline, "
                + "outputs [{path, preset, duration, bytes, exists, completedAt}] newest first, recipe, thumbnail}; "
                + "progress is null before the first stage entry of the run."),
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
                + "section, and its onScreen note when the beat has one; overall similarity and extra heard words.",
            parameters: [
                CommandParameter("beats", .array, "Beats [{id, text, section}] as JSON", cli: .option("beats")),
                CommandParameter("text", .string, "The whole script as one beat", cli: .option("text")),
            ]),
    ]

    /// The edit as one list: check it without touching the timeline, then build it as one edit.
    static let planCutSpecs: [CommandSpec] = {
        let cut = CommandParameter(
            "cut", .object, "The list {clips, titles, music} (CLI: path to cut.json); plan.cut when omitted",
            cli: .positionalJSONFile)
        let patch = CommandParameter(
            "patch", .object, "Changes merged over the list instead of a whole new one: {clips: {c2: {cover: […]}, c5: null}, "
                + "titles: {t1: {style: {…}}}}; an entry by ID merges, null removes, an unknown ID adds",
            cli: .option("patch"))
        let shape = "plan.cut is {clips: [{id, media, quote | words FIRST-LAST | from/to seconds (whole media when "
            + "none; seconds for a still; from or to next to a quote or words moves that edge, and a patched quote "
            + "drops the old edges), section, speed, volumeDb, role (speech, broll, underVO; speech by default "
            + "for quote, words or seconds holding transcribed words), zoom, pan, tilt (its picture's framing: a punch-in such as zoom 1.15 "
            + "breaks a jump cut between two clips of one camera), focus: [x, y, w, h] (a rectangle of its source in "
            + "pixels, such as a panel of a screen recording: apply works out zoom, pan and tilt like clip motion --focus; "
            + "not with zoom, pan, tilt or their keyframes), focusTo (moved to by its last frame), focusKeys: [{at "
            + "(source seconds), rect [x, y, w, h], move (seconds, default 0.5)}] (one panel after another: each held "
            + "until the next key, eased in over move), within (where the rectangle lands: auto, the band no opaque "
            + "picture on a higher layer covers edge to edge such as the bottom half under a camera overlay; full; "
            + "top-half, bottom-half, left-half, right-half; or [x, y, w, h] in canvas shares or pixels), ease (of the "
            + "moves), backdrop, crop, keyframes, fill, color (item fields of its "
            + "picture; null clears one set by hand), cover: [{media, from, seconds, zoom, pan, tilt, focus, focusTo, "
            + "focusKeys, within, ease, backdrop, crop, "
            + "keyframes, fill, color}] (pictures shown over the clip's sound, muted, the last filling the rest), overlays: "
            + "[{media (default the clip's own), from (source seconds; default in sync with the clip for its own media), "
            + "offset (seconds into the clip), seconds (default the rest of the clip), zoom, pan, tilt, focus, focusTo, "
            + "focusKeys, within, ease, backdrop, crop, "
            + "keyframes, fill, color}] (pictures over the clip on an overlay layer, muted, rebuilt and moved with it: a "
            + "picture-in-picture), transition (the cut into it from the clip before)}], voiceover: [{id, text, "
            + "caption (what captions show, such as digits), section, pause (seconds after it), at (seconds; else "
            + "right after the line before), take (a kept take's "
            + "path; else the best kept take of its text: voice lines makes them), volumeDb}] (on the Voiceover "
            + "layer from 0; an edit may be lines without clips), graphics: [{id, media, on (a clip, line, title or "
            + "earlier graphic) | section | at, offset, seconds | until (an entry: to its end), else to its anchor's "
            + "end, track overlay|main (main: the picture of an edit made of graphics), from, render (a graphics "
            + "plugin's inputs, not read), transition (the cut into it on its layer), enter, exit (its own In and Out)}] "
            + "(full canvas), titles: [{id, text, clip "
            + "(a clip or line) or section (+ offset seconds) | at, seconds (to "
            + "the end of its clip or section when left out; needed with at), preset, style, enter, exit}], captions: {from: "
            + "speech, wordStyle highlight|karaoke|reveal, preset, style, replace: {\"misheard words\": \"right "
            + "words\"} (names the transcript got wrong; a line a clip plays only part of shows only the words heard), maxChars "
            + "(voiceover lines break into cues of at most this many characters)} "
            + "(captions from the "
            + "stored transcripts of the clips' media, cut with them, and each voiceover line's own text timed by its "
            + "take's words), music: {media, from, volumeDb (unset: plan apply sets one fixed level underVoiceDb "
            + "under the measured voice), underVoiceDb (default 16), duck (default false: no ducking), duckDb (level "
            + "under speech; turns ducking on), duckMinGapSeconds (default 2.5: shorter gaps between lines keep the "
            + "music down)}, sfx: [{id, media, on (a clip, line, title or graphic ID) | section | at seconds, offset (negative: "
            + "before it), seconds (default the whole file), volumeDb}] (on the SFX layer, never past the end), "
            + "review: {limit: number} (review limits such as minTextSize, minTextContrast, "
            + "minShotSeconds, chosen from the recipe's ranges; merged over the project's review on apply)}; any "
            + "entry may give facts: [key] (the project facts or claims it rests on). A transition, enter or exit is "
            + "\"kind\", \"kind:frames\" (such as \"dissolve:12\"), {kind, duration (frames), easing} or \"none\" (removes one "
            + "set by hand); kinds as on upsertTransition; default length half a second. A title's "
            + "preset is a renderer "
            + "preset (" + TextPreset.all.joined(separator: ", ") + ") or a library text-preset ID (templates such "
            + "as stacked-keyword, boxed-keyword, headline-subline, two-tone-pop; library list --kind text-preset); "
            + "its style gives text style fields over the preset's: font (a PostScript name or System-[Condensed|"
            + "Compressed]Bold|Heavy|Black; fonts list --covers), size (share of the short side), fill, stroke, "
            + "strokeWidth (points, 0–50), positionX (0 left … 1 right), positionY (baseline height from the "
            + "bottom: 0.1 low, 0.86 high), align, uppercase, lineHeight, tracking, background {color, opacity, "
            + "padding, radius (× font size, not pixels: 0.2 rounds the corners)}, shadow {color, opacity, blur, "
            + "dx, dy}; other keys are item properties. Over bright "
            + "or busy footage give a stroke or a background. A font missing letters of the content language is an error."
        return [
            CommandSpec(
                "plan.check", .read,
                "Check the edit list before building it, without changing anything: each clip's source range "
                    + "(quotes resolved in the stored transcript, edges inside a word or sentence, how much of the "
                    + "quote was heard), where it lands, its described shot and orientation; each title's chars per "
                    + "second and textShare (its smallest line as a share of the short side, the measure of "
                    + "review.minTextSize); problems {id, severity error|warning|info, entry, detail, facts} (quote not found, "
                    + "unknown media, source played twice, same media and size back to back, media against the canvas "
                    + "shape, entry-invalid for each entry it cannot read (all of them at once), transition-no-cut and "
                    + "transition-too-long, stroke-units, plate-units, unknown-field for a field nothing reads, "
                    + "unknown-fact for a facts key that "
                    + "is neither a project fact nor a claim, "
                    + "review-profile-unset with facts.unsetLimits: every review limit the "
                    + "built edit needs and nobody set); and the review of the edit as it would be (the "
                    + "project's review profile; picture and loudness need a render and are not measured). ok is false "
                    + "while an error stands. Voiceover lines report at, seconds, take and the take's similarity; "
                    + "graphics their at, seconds and track (also before they have media, so a graphics plugin renders "
                    + "each to its span; words adds the voiceover words heard during each, in seconds from its start). "
                    + "save keeps the list (cut, or patch merged by entry ID) as plan.cut without building it, as one "
                    + "undoable edit, when its only errors are ones a later stage resolves ("
                    + PlanCut.stagePending.sorted().joined(separator: ", ") + "); else it refuses with the problems. "
                    + "The result is the check's with rev and saved. "
                    + shape,
                parameters: [
                    cut, patch,
                    CommandParameter(
                        "words", .boolean, "Per graphic, the voiceover words heard during it (seconds from its start)",
                        cli: .flag("words")),
                    CommandParameter(
                        "save", .boolean, "Save the list as plan.cut without building (needs baseRev)", cli: .flag("save")),
                    CommandParameter(
                        "baseRev", .integer, "With save: the current project revision, or \"last\"", minimum: 0,
                        cli: .option("base-rev")),
                ]),
            CommandSpec(
                "plan.apply", .edit,
                "Build the edit list as one undoable edit: clips on Main in order (sound linked on the dialogue "
                    + "layer), voiceover lines, graphics, section markers, titles and the music bed, each tagged planCut. Applying again replaces "
                    + "only what an earlier apply built, and keeps what was changed on those items by hand since: a field "
                    + "changed by hand that the list did not change since stays, one the list changed too takes the list's "
                    + "value (volumeDb, muted, fades, crop, keyframes, backdrop, fill, color, a title's text, transform and "
                    + "textStyle key by key; the pieces a ripple cut, split or trim left of a clip while its row gives the "
                    + "same range; where a line, title, graphic or sound starts; the music bed's level and span; a clip's "
                    + "speed or curve unless the list gives speed; cut transitions and In/Out). handEdits lists each one "
                    + "kept and each one overwritten (item, entry, field, hand, list), also with dryRun: check it before "
                    + "applying, and move a value into plan.cut to make it the list's. A row's null picture field clears a "
                    + "hand edit. Other layers are kept but not re-timed: give a picture that must follow a clip as its "
                    + "overlays; Main must hold nothing else. Captions it built, regrouped with captions group too, stay "
                    + "as they are while the list would make the same ones (captionsKept: true); when it would not they are "
                    + "replaced, and the new ones grouped as captions group grouped the old (the same rule, or the same "
                    + "words together), without the words a built clip played with no caption over them (cues deleted by "
                    + "hand stay deleted); speech captions it did not build where its captions go are an error, never a "
                    + "second set. Refuses while plan.check has an error (plan check --save keeps a list not ready to build). "
                    + "With cut or patch, the list is also saved as plan.cut in the same edit (a revision: --patch with "
                    + "only what changes, then nothing else to write); plan.cut.review is merged into the project's "
                    + "review in the same edit. dryRun returns the check. The "
                    + "result has the review's errors and warnings of the built edit (no info rows; picture and "
                    + "loudness need review measure); sheet adds the storyboard image paths (timeline sheet --cuts "
                    + "--text) of the new revision. The result is brief (clips as a count; the per-clip facts are plan "
                    + "check's); full adds clips, changes, items and the sheet's cells. " + shape,
                parameters: [
                    cut, patch,
                    CommandParameter("dryRun", .boolean, "Check without editing", cli: .flag("dry-run")),
                    CommandParameter("sheet", .boolean, "Also lay the new revision out on a contact sheet", cli: .flag("sheet")),
                    CommandParameter("full", .boolean, "Return every clip's facts, the changes and the built items",
                                     cli: .flag("full")),
                    CommandParameter("why", .string, "Why this edit, in one sentence (up to 500 characters)", cli: .option("why")),
                    CommandParameter("evidence", .string, "What it rests on, separated by ;", cli: .option("evidence")),
                    baseRevision,
                ]),
        ]
    }()

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
                + "music). An edge inside a transcribed word widens to the word's edge (listed in widened); returns "
                + "the new item IDs.",
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
                + "from the centre. With title, the text is drawn on each cover in preset (a text preset or a library "
                + "text-preset ID, bold-outline by default), at title-size of each cover's short side (default 0.12, "
                + "about 7 % of a 9:16 cover's height; a starting point) and fitted to its width; "
                + "each cover gives titleBox {x, y, width, height} as fractions from the top-left, to check against the "
                + "platform's zones (platforms get), and its file ends in -title. Pick the frame from real frames "
                + "(timeline sheet); look at the result.",
            parameters: [
                CommandParameter("frame", .integer, "Timeline frame", required: true, minimum: 0, cli: .positional),
                CommandParameter("aspect", .string, "Aspects such as 16:9,9:16", cli: .option("aspect")),
                CommandParameter("size", .integer, "Long edge in pixels", minimum: 160, maximum: 3_840, cli: .option("size")),
                CommandParameter("title", .string, "Title text drawn on each cover", cli: .option("title")),
                CommandParameter("preset", .string, "Text preset of the title", cli: .option("preset")),
                CommandParameter("titleSize", .number, "Title size as a fraction of the cover's short side (default "
                                 + "0.12)", range: 0.02...0.4, cli: .option("title-size")),
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
