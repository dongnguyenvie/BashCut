import BashCutProject
import Foundation

extension CommandCatalog {
    static let reviewSpec = CommandSpec(
        "review.run", .read,
        "Review the timeline before export: issues {id, kind, severity error|warning|info, title, detail, frame, "
            + "endFrame?, facts {raw numbers}, fix? {command?, arguments?, hint?}}, errors first. Invariants (gaps, black "
            + "picture, cut-in-word, missing fonts or glyphs, output length and shape, true peak) are always checked; "
            + "editorial checks only against the limits in the project's review object, and nothing without them. IDs "
            + "are anchored to clips. With summary: {issues, summary, checks (measured, stale, notChecked, failed, "
            + "unreliable, unsetLimits: only limits a check of this timeline reads, atExport: loudness until a "
            + "normalized export measures it)} and summary.status: fail (errors), incomplete (no errors, but a limit "
            + "unset or a check not run; atExport does not count) or pass (passed is status == pass; the CLI exits 0, "
            + "1 or 2); a pass by an agent is recorded as the review stage unless a stage the plan requires before review "
            + "is still open (listed in stagesPending); with sinceRev also diff "
            + "{fixed, new, persisting}. With measure, a revision not measured yet is measured first (review.measure, "
            + "waited for up to 100 s; measured {job, timedOut} says so), so one call measures and reviews. With from/to only "
            + "the issues touching those frames are listed and counted (range in the result; a pass is not the review "
            + "stage), the check after a quick edit. Issues kept with review accept are left out of the list (their IDs "
            + "in acceptedHidden with summary; counted as accepted) unless accepted is given, which lists them with "
            + "accepted {reason}.",
        parameters: [
            CommandParameter("measure", .boolean, "Run review measure first when this revision is not measured, and "
                             + "wait for it", cli: .flag("measure")),
            CommandParameter("sinceRev", .integer, "Compare with the review of this revision (this session)", minimum: 0,
                             cli: .option("since-rev")),
            CommandParameter("minSeverity", .string, "Leave out issues less severe than this",
                             choices: ReviewSeverity.allCases.map(\.rawValue), cli: .option("min-severity")),
            CommandParameter("summary", .boolean, "Wrap the issues with counts and a status",
                             cli: .flag("summary")),
            CommandParameter("accepted", .boolean, "Also list the issues kept with review accept",
                             cli: .flag("accepted")),
            CommandParameter("from", .integer, "Only issues that touch frames from here (with to: [from, to))",
                             minimum: 0, cli: .option("from")),
            CommandParameter("to", .integer, "Only issues that touch frames before this one", minimum: 1,
                             cli: .option("to")),
        ])

    /// The CLI's exit status for a successful call: `review run --summary` exits 1 on fail and 2 on incomplete
    /// (spec 13 §6.3), every other result 0. Error statuses are `RPCFailure.exitStatus` (64 and up).
    public static func exitStatus(method: String, result: JSONValue?) -> Int32 {
        guard method == "review.run" else { return 0 }
        switch result?.object["summary"]?.object["status"]?.string {
        case "fail": return 1
        case "incomplete": return 2
        default: return 0
        }
    }

    static let reviewAcceptSpec = CommandSpec(
        "review.accept", .edit,
        "Keep an issue on purpose, with the reason, as one undoable edit (review.accepted); later runs show it "
            + "with accepted.reason, leave it out of the counts, and the export report lists it. Accept an error "
            + "only when no fix exists (the summary counts it as acceptedErrors); to change a whole check, set "
            + "review.severities.<check> to {severity, reason}. With remove, the issue counts again.",
        parameters: [
            CommandParameter("id", .string, "Issue ID from review run", required: true, cli: .positional),
            CommandParameter("reason", .string, "Why it stays", cli: .option("reason")),
            CommandParameter("remove", .boolean, "Count the issue again", cli: .flag("remove")),
            baseRevision,
        ])

    static let reviewVerifySpec = CommandSpec(
        "review.verify", .read,
        "Prove a fix: the issue as an earlier review of this session saw it (before, beforeRev) against now, measured "
            + "over the issue's own range and a second around it (picture issues re-sample just that range; others "
            + "re-run the review), status fixed or persisting, other issues nearby, and window: a still strip of the "
            + "range with the cuts, words and levels. Loudness needs a normalized export of the revision. Several IDs "
            + "(comma-separated) or all (the errors and warnings of the last earlier review) are proved in one call: "
            + "fixed and persisting counts, a row per issue (a window only for what persists) and new issues.",
        parameters: [CommandParameter("id", .string, "Issue ID, ID1,ID2,… or all", required: true, cli: .positional)])

    static let reviewPacketSpec = CommandSpec(
        "review.packet", .read,
        "Write an evidence folder for a fresh critic (a sub-agent with only this folder and bc:review): README, "
            + "plan.json (brief, plan, review profile, outputs), digest.json (what changed since the last review round), "
            + "issues.json (with the round diff), shots.json (review.shots with summary), word-landing.json (words against "
            + "cuts and titles), coverage.json (described shot per clip, script beats heard), measured.json (what was and was not "
            + "measured), checks.json (the kit's generic checks, plan.checks and plan.promise) and a contact sheet of every "
            + "cut and title. No editor reasons are included. point picks the audit: draft (default, this folder), "
            + "strategy (brief with inferred fields, plan, checks, a sheet when the timeline has one, missing) or process "
            + "(run checklist, run log, timeline changes).",
        parameters: [
            CommandParameter("point", .string, "Audit point (default draft)", choices: WorkflowChecklist.auditPoints,
                             cli: .option("point")),
        ])

    static let reviewCompareSpec = CommandSpec(
        "review.compare", .read,
        "A reference and our render, both imported and measured (media analyze), side by side by the same functions: "
            + "duration, shots and shot-length median/p25/p75, cuts per minute, picture medians (luma, spread, change, "
            + "colourfulness, sharpness), sound level median/p10/p90/range and peak, each with ours − reference. No "
            + "verdict; a metric gets within only when the project's review.compare sets its tolerance.",
        parameters: [
            CommandParameter("reference", .string, "Reference media ID", required: true, cli: .option("reference")),
            CommandParameter("ours", .string, "Our render's media ID", required: true, cli: .option("ours")),
        ])

    static let reviewMeasureSpec = CommandSpec(
        "review.measure", .read,
        "Run the measured review for this revision and keep it, so review.run includes it: render the timeline "
            + "small (two frames a second and both sides of every hard cut on Main, proxies allowed) for black or "
            + "empty picture, frozen picture, long static shots and jump cuts, the contrast of every title and up to "
            + "eight captions against the picture behind them (review.minTextContrast, a WCAG ratio; unset: the "
            + "lowest as info), and run every enabled plugin "
            + "review.check side by side (each at most 30 s; a failing or slow check becomes an info issue). Plugin "
            + "issues carry source (the plugin ID) and IDs prefixed with the provider. A project turns checks off "
            + "with review.disabledChecks (plugin or provider IDs; timeline apply setProjectProperties). The job's "
            + "result has the sample count, hardCuts (touching clips on Main without a transition, the ones measured), "
            + "the plugin checks that ran and the measured issues; measure again after an edit.",
        parameters: [
            CommandParameter("picture", .boolean, "Measure the picture (default true)", cli: .option("picture")),
            CommandParameter("plugins", .boolean, "Run plugin review checks (default true)", cli: .option("plugins")),
        ],
        execution: .job)

    static let reviewPictureSpec = CommandSpec(
        "review.picture", .read,
        "Read the raw picture measurement of the last review.measure: per sample {frame, seconds, luma, spread, "
            + "change, peak} at a fixed interval and per hard cut on Main {item, fromItem, frame, before, seconds, "
            + "difference}, with the units and the noise floors the picture checks use (floors). Values are fractions "
            + "of full scale on a small grey thumbnail. current is false when the timeline changed since; measure "
            + "again for this revision. No verdicts: read the numbers to find frozen stretches, flat or dark picture "
            + "and near-identical cuts.",
        parameters: [
            CommandParameter("from", .integer, "First timeline frame (default 0)", minimum: 0, cli: .option("from")),
            CommandParameter("to", .integer, "Timeline frame after the range (default: the end)", minimum: 1,
                             cli: .option("to")),
            CommandParameter("samples", .boolean, "Include the samples (default true)", cli: .option("samples")),
            CommandParameter("cuts", .boolean, "Include the cuts (default true)", cli: .option("cuts")),
        ])

    static let reviewShotsSpec = CommandSpec(
        "review.shots", .read,
        "Read the shots on Main in order: index, id, at/atSeconds, duration (frames) and seconds, media, mediaKind, "
            + "sourceIn and sourceInSeconds, zoom and transform, speed, keyframed properties, freezeFrame/reverse when "
            + "set, gapBefore (frames since the previous shot), transitionIn {kind, duration, easing} or the picture "
            + "cutDifference across a hard cut, and motion {mean, peak, samples} (fractions of full scale, see "
            + "review.picture) when review.measure ran for this revision (pictureMeasured), described (the "
            + "media.describe facts of the source shot it plays), cameraMove [{property, from, to, perSecond, unit, "
            + "ease}] from its keyframes, and cut (into it): kind (hard or the transition's kind), sameMedia, "
            + "sameSetup (same media, overlapping or adjacent source), sourceGapSeconds, framingBefore/After {zoom, "
            + "pan, tilt} (keyframes included), sameFraming, size/move/direction {from, to} when described. With "
            + "from/to, only the shots that overlap those frames. No verdicts. With summary: count, total, mean, "
            + "median, min and max seconds and cuts per minute; rhythm {overall, sections [per section marker]} with "
            + "mean, median, cv, cutsPerMinute, mode (the most common length bin and its share); shares of each size, "
            + "move and direction. With media: the same for a source file's measured shots (media.analyze) and its "
            + "descriptions.",
        parameters: [
            CommandParameter("summary", .boolean, "Add statistics, rhythm and shares", cli: .flag("summary")),
            CommandParameter("from", .integer, "Only shots that end after this timeline frame", minimum: 0,
                             cli: .option("from")),
            CommandParameter("to", .integer, "Only shots that start before this timeline frame", minimum: 1,
                             cli: .option("to")),
            CommandParameter("media", .string, "Read a source file's measured shots instead of Main",
                             cli: .option("media")),
            CommandParameter("minScore", .number, "With media: lowest cut score (default 0.1)", range: 0...1,
                             cli: .option("min-score")),
        ])

    /// Cuts, text, captions and sound effects timed against beats and words (P0-B2).
    static let reviewSyncSpec = CommandSpec(
        "review.sync", .read,
        "Time events against the beat grid and the spoken words: per event (cuts on Main by default; text items "
            + "and sfx items on request) the nearest beat and the nearest word edge (start or end, its text, "
            + "whether the event falls inside the word) with offsetFrames and offsetMs (positive = after it), and "
            + "for beats and words count, mean and median offset (with bins also p10, p90 and counts per offset "
            + "from −6 to +6 frames). Words are the stored transcripts heard through the clips (media.transcribe), "
            + "else the caption words. With rendered: rendered {windows [{at, lagMs, correlation}], "
            + "driftMsPerMinute, lagStartMs, lagEndMs} from matching the last export's sound to the timeline's mix "
            + "every 10 s (positive lag = the render is later); the export must show this revision. "
            + "impacts adds impacts {summary {count, perMinute, minSpacingSeconds, minSpacingBeats, "
            + "onStrongestQuarterOfBeats}, events [{frame, frames, source transition|keyframes|overlay, item, kind or "
            + "changes {property: [from, to]} or media, beat {frame, offsetFrames, strength}, secondsSincePrevious, "
            + "beatsSincePrevious}]}: changes to the whole picture lasting at most impactFrames (transitions on Main, "
            + "fast zoom/pan/tilt/rotation/opacity/exposure keys on Main clips and adjustment layers, short pictures "
            + "over Main). sfx adds sfxRuns [{media, count, items, frames, gainsDb, intervalsFrames, constantGain, "
            + "constantSpacing}]: three or more placements of one sound file with starts at most runGapSeconds apart. "
            + "No limit is applied.",
        parameters: [
            CommandParameter("events", .string, "cuts, text, sfx, captions, impacts (comma separated; default cuts)",
                             cli: .option("events")),
            CommandParameter("impactFrames", .integer, "Longest impact, frames (default 12)",
                             minimum: 1, maximum: 120, cli: .option("impact-frames")),
            CommandParameter("runGapSeconds", .number, "Largest gap in an sfx run, s (default 2)",
                             cli: .option("run-gap-seconds")),
            CommandParameter("bins", .boolean, "Add p10/p90 and counts per offset", cli: .flag("bins")),
            CommandParameter("rendered", .boolean, "Also measure the last export's timing against the timeline",
                             cli: .flag("rendered")),
        ])

    static let uiFrameSpec = CommandSpec(
        "ui.frame", .read,
        "Render the viewer's picture at a timeline frame (the playhead by default) to a PNG, like attaching the "
            + "viewer frame in Ask; returns its path. Read the file to look at the edit. Keeps the ten newest. width "
            + "renders it that many pixels wide (phone: 390, about a phone screen, to judge text at the size viewers "
            + "see it); otherwise up to 1280 on the long edge. out also copies the PNG to that file (replacing it).",
        parameters: [
            CommandParameter("frame", .integer, "Timeline frame; the playhead by default", minimum: 0, cli: .positional),
            CommandParameter("width", .integer, "Width in pixels", minimum: 64, maximum: 4_096, cli: .option("width")),
            CommandParameter("phone", .boolean, "390 pixels wide", cli: .flag("phone")),
            CommandParameter("out", .string, "Also write the PNG to this file", isPath: true, cli: .option("out")),
        ])

    /// Before/after grids (P0-B5).
    static let uiFramesSpec = CommandSpec(
        "ui.frames", .read,
        "Compare pictures in one PNG grid, one row per frame: compare graded puts the frame without colour (looks, "
            + "adjustments, LUTs bypassed) next to the edit as graded; compare source puts the source frame of the "
            + "clip on Main at that point (no reframe, no grade) next to the edit. Rows from frames (timeline "
            + "frames) or items (the middle of each item). Each cell is width pixels wide (default 390). Returns "
            + "{path, rows [{frame, item?, sourceSeconds?}], columns}.",
        parameters: [
            CommandParameter("compare", .string, "graded or source", required: true, choices: ["graded", "source"],
                             cli: .option("compare")),
            CommandParameter("frames", .string, "Timeline frames, comma separated", cli: .option("frames")),
            CommandParameter("items", .string, "Item IDs, comma separated", cli: .option("items")),
            CommandParameter("width", .integer, "Cell width in pixels (default 390)", minimum: 64, maximum: 2_048,
                             cli: .option("width")),
        ])

    /// The composed timeline as pictures without exporting (P0-B3, P0-B4).
    static let timelineStillsSpecs: [CommandSpec] = [
        CommandSpec(
            "review.window", .read,
            "Look across a moment of the edit without exporting: one PNG with the composed frames from frame − span "
                + "to frame + span (every step frames) labelled with their time, the cuts on Main drawn as lines, the "
                + "timeline's sound level (−60…0 dBFS) and the words heard there. Returns {path, frames, cuts, words "
                + "[{text, at, end}], levels [{frame, db}] (the mix per frame, null without sound)}.",
            parameters: [
                CommandParameter("frame", .integer, "Timeline frame in the middle", required: true, minimum: 0,
                                 cli: .positional),
                CommandParameter("span", .integer, "Frames on each side (default 6)", minimum: 1, maximum: 120,
                                 cli: .option("span")),
                CommandParameter("step", .integer, "Frames between pictures (default 1)", minimum: 1, maximum: 60,
                                 cli: .option("step")),
                CommandParameter("width", .integer, "Image width in pixels (default 1600)", minimum: 400,
                                 maximum: 8_192, cli: .option("width")),
            ]),
        CommandSpec(
            "timeline.sheet", .read,
            "Lay the composed edit out on contact sheets without exporting: cells at listed frames (at: numbers, "
                + "first, last), at every cut on Main (cuts), in the middle of every title (text) and every N seconds "
                + "(every; 2 s when nothing else is asked), labelled '<cell> <m:ss.s>'. Returns {sheets [{path, "
                + "output, firstCell, cells}], cells [{cell, frame, seconds, items on screen, text on screen}], index "
                + "(the same as index.json), cached}. Kept per revision and request in .bashcut/cache/timeline-sheets. "
                + "With outputs (all: the project's outputs; or preset names) another set of sheets per output of the "
                + "frame's shape with the zones its interface covers shaded.",
            parameters: [
                CommandParameter("at", .string, "Frames, comma separated; first and last allowed", cli: .option("at")),
                CommandParameter("cuts", .boolean, "A cell at the start of every shot on Main", cli: .flag("cuts")),
                CommandParameter("text", .boolean, "A cell in the middle of every title", cli: .flag("text")),
                CommandParameter("entries", .string, "plan.cut entry IDs, comma separated (c2,t1): a cell in the middle "
                                 + "of each item built for them, to look at only what a revision changed",
                                 cli: .option("entries")),
                CommandParameter("every", .number, "Seconds between cells", range: 0.1...3_600, cli: .option("every")),
                CommandParameter("size", .integer, "Long edge of each cell in pixels (default 320)", minimum: 64,
                                 maximum: 2_048, cli: .option("size")),
                CommandParameter("columns", .integer, "Cells per row (default 8 portrait, 6 landscape)", minimum: 1,
                                 maximum: 24, cli: .option("columns")),
                CommandParameter("rows", .integer, "Rows per sheet (default 3 portrait, 6 landscape)", minimum: 1,
                                 maximum: 24, cli: .option("rows")),
                CommandParameter("outputs", .string, "all, or export preset names: sheets with each one's zones",
                                 cli: .option("outputs")),
            ]),
    ]

    /// Colour as numbers (P0-B8).
    static let colorMeasureSpec = CommandSpec(
        "color.measure", .read,
        "Measure colour per clip on frames spread over each clip (samples, default 3), on the scale the colour skill "
            + "reads (0–100): black (luma p1), p5, mid (p50), p95, white (p99), mean, saturation (mean HSV) and "
            + "saturationP95, tintShadows/Mids/Highlights [R−B, G−(R+B)/2] (bands split at luma 0.25 and 0.7; null "
            + "with too few pixels), clippedShare and crushedShare; the median over the samples. By default the "
            + "source frames (no reframe, no grade); graded measures the edit as composed; compare source measures "
            + "the edit without colour and as graded and adds change {black, mid, white, saturation, tintMids, "
            + "chromaRatio, blackLift, clippedGrowth, crushedGrowth, meanDeltaE (CIE76)}. by clip adds the median "
            + "clip and each clip's difference from it. Clips on Main by default, or the given video item IDs. Facts "
            + "only.",
        parameters: [
            CommandParameter("items", .string, "Video item IDs, comma separated; the clips on Main by default",
                             cli: .option("items")),
            CommandParameter("samples", .integer, "Frames per clip (default 3)", minimum: 1, maximum: 24,
                             cli: .option("samples")),
            CommandParameter("graded", .boolean, "Measure the edit as composed", cli: .flag("graded")),
            CommandParameter("compare", .string, "source: the edit without colour against it as graded",
                             choices: ["source"], cli: .option("compare")),
            CommandParameter("by", .string, "clip: each clip's difference from the median clip", choices: ["clip"],
                             cli: .option("by")),
        ])

    /// Platform facts the checks use (#469).
    static let platformsGetSpec = CommandSpec(
        "platforms.get", .read,
        "Read the platform facts review uses: per platform (TikTok, Reels, Shorts, YouTube) shape, maxSeconds, "
            + "targetLUFS, maxTruePeakDbTP and safeArea (zones the app covers, as fractions), with the project's "
            + "review.platform overrides applied, whether it is one of the project's outputs and whether it was "
            + "overridden; layout: the zones text is checked against (the strictest of the outputs of the frame's "
            + "shape, null when none); targets: each output preset's loudness target (output.targets, else the "
            + "platform's); data: the platform table's version and origin (built-in or the plugin that shipped a newer "
            + "one). With facts, every field with {value, kind hard|recommended|info, source, checked, confidence}, "
            + "including bitrateMbps, post text limits (title.maxChars, description.maxChars, caption.maxChars, "
            + "hashtags.max, hashtags.ignoredAbove), cover facts, chapter and disclosure rules where known. With id, "
            + "that one platform's row with its facts.",
        parameters: [
            CommandParameter(
                "id", .string, "tiktok, reels, shorts, youtube, or an export preset (youtube-1080 → youtube)",
                cli: .positional),
            CommandParameter("facts", .boolean, "Include each field's provenance", cli: .flag("facts")),
        ])

    static let reviewLayoutSpec = CommandSpec(
        "review.layout", .read,
        "Read where text sits as the renderer lays it out: per visible text item id, track, trackRole, at/end, text, "
            + "preset, lines, longestLineChars, fontPixels and fontShare (of the frame's short side), bounds (pixels "
            + "from the top-left) and edges (distance to each frame edge as a share of that dimension, negative "
            + "outside), keyframed when keyframes move it (not followed); holdSeconds, words and wordsPerSecond; "
            + "speech {onsetOffsetFrames (from the nearest word start), narrationShare (of its time with words "
            + "spoken)} from the heard or caption words; captionOverlap {item, ratio of its box} for titles; "
            + "templateRepeats (items with its preset on its layer); faceOverlap {ratio (largest share of one face box "
            + "the text box covers), frame, item and media of the clip, confidence, samples (pictures with a face while "
            + "it shows)} from the face boxes media subjects stored for the clips under it (placed with fit/fill, zoom, "
            + "pan and tilt; null when none are stored: unknown, not \"no face\"; review.maxFaceOverlap turns it into "
            + "a text-face review issue). With contrast: contrast {ratio (WCAG, 1–21; basis "
            + "mean: of the mean text, outline: the stronger of fill and outline, plate: the letters against their box), "
            + "meanRatio, lightRatio and darkRatio (the light and dark parts of the text, such as fill and outline), "
            + "textLuminance, "
            + "backgroundLuminance, textPixels} measured on the frame with and without text (at frame, or each "
            + "item's middle). Also the frame size, the platform whose zones apply (safeArea, minTextSize), density "
            + "(titles and captions per minute), facesProvider (face boxes are stored for a clip on screen) and, at a "
            + "frame, pictures on screen with their scale and coverage (and faceOverlap of an overlay's box with the "
            + "faces of the other clips). "
            + "With from/to, only text that overlaps those frames. With ink: ink {frame, luma, mid (0–100), inkShare "
            + "(pixels text and overlay layers change)} of the composed frame (frame, default 0) against Main alone. "
            + "No verdicts.",
        parameters: [
            CommandParameter("frame", .integer, "Only text on screen at this timeline frame", minimum: 0,
                             cli: .option("frame")),
            CommandParameter("from", .integer, "Only text that ends after this timeline frame", minimum: 0,
                             cli: .option("from")),
            CommandParameter("to", .integer, "Only text that starts before this timeline frame", minimum: 1,
                             cli: .option("to")),
            CommandParameter("ink", .boolean, "Measure the composed frame (frame, default 0): luma, mid and inkShare",
                             cli: .flag("ink")),
            CommandParameter("contrast", .boolean, "Measure each item's contrast on rendered frames",
                             cli: .flag("contrast")),
        ])

    /// Read-only sound analysis through plugin providers; each runs as a job whose result holds the values.

    static let analysisSpecs: [CommandSpec] = [
        CommandSpec(
            "audio.measure", .read,
            "Measure a media file's sound with an audio.loudness provider: integrated loudness (LUFS), true peak, "
                + "loudness range (LU) and the energy share in the speech band (300-3000 Hz) and the presence band "
                + "(1-4 kHz, where consonants carry words). With curve, loudness over time: curve {step 0.1 s, "
                + "momentary (400 ms) and shortTerm (3 s) LUFS, peakDb per step}. With timeline (instead of media), "
                + "the whole mix is rendered to a scratch file (no export) and measured with its curve and silences "
                + "[{start, end, seconds}] where momentary loudness stays at or under −70 LUFS. The job's result holds "
                + "the values.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", cli: .option("media")),
                CommandParameter("curve", .boolean, "Add loudness over time", cli: .flag("curve")),
                CommandParameter("timeline", .boolean, "Measure the timeline's mix instead of a media file",
                                 cli: .flag("timeline")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "beats.grid", .read,
            "Read the beat grid beats detect stored for a media file, in its own seconds: bpm, beatsSeconds and, when "
                + "the provider gives them, grid {strengths (0–1 per beat), downbeats and beatsPerBar (the phase where "
                + "the kick band hits hardest; phaseScores per phase), confidence (how much the tempo stands out, 0–1), "
                + "fit {periodSeconds, phaseSeconds, rmsErrorMs of the beats from a straight grid}, alternates [{bpm "
                + "half and double, relative strength}]}, and downbeatFrames on the timeline where the media plays.",
            parameters: [mediaMedia]),
        CommandSpec(
            "audio.energy", .read,
            "How a music file's energy moves, with an audio.energy provider: the curve every step seconds — levelDb, "
                + "onset (density) and fullness (share of octave bands near the loudest) — and timeline [{item, at, fromSeconds, "
                + "toSeconds}] where the file plays. Picking lifts and drops is yours. A job.",
            parameters: [
                mediaMedia,
                provider,
            ],
            execution: .job),
        CommandSpec(
            "media.subjects", .read,
            "Faces and people in the picture of a video or image, with a vision.faces provider (built in: Apple "
                + "Vision): frames [{seconds, frame (source), faces [{box, confidence}], people [{box, confidence}]}] "
                + "one picture every step source seconds over from…to; box is [x, y, width, height] as shares of the "
                + "upright picture from the top left. timeline [{item, at, fromSeconds, toSeconds}] places a second. "
                + "No labels: which face is the speaker or matters is yours. The boxes are kept per file (merged "
                + "with earlier runs) for clip.reframe and review.layout's faceOverlap. A job.",
            parameters: visionParameters, execution: .job),
        CommandSpec(
            "media.ocr", .read,
            "On-screen text in the picture of a video or image, with a vision.text provider (built in: Apple Vision): "
                + "frames [{seconds, frame (source), text [{string, box, confidence}]}] one picture every step source "
                + "seconds over from…to, lines top to bottom; box as in media.subjects. Use it to read a reference's "
                + "text cards and caption placement. Whether a line is a caption, a title or a sign is yours. A job.",
            parameters: visionParameters + [
                CommandParameter("languages", .string, "BCP 47 languages to try in order, comma separated (default: "
                                 + "the provider picks)", cli: .option("languages")),
            ], execution: .job),
        CommandSpec(
            "image.cutout", .ui,
            "Remove a picture's background with a vision.cutout provider (built in: Apple Vision): the subject (a "
                + "mascot, a product, a person) on a transparent background as a PNG in the project's generated "
                + "folder. source is an image file (relative to the project or absolute) or a library sticker ID. "
                + "Returns path, projectPath, width, height, instances (subjects found) and coverage (share of the "
                + "picture kept). Look at it, then library add --kind sticker --file it (or library update the "
                + "sticker) to use it. A job.",
            parameters: [
                CommandParameter("source", .string, "Image file or library sticker ID", required: true, cli: .positional),
                CommandParameter("crop", .boolean, "Crop to the subject", default: .bool(false), cli: .flag("crop")),
                provider,
            ], execution: .job),
        CommandSpec(
            "audio.mix-measure", .read,
            "Read the mix by role without exporting: one stem each for speech (dialogue and voiceover layers and the "
                + "sound of video clips), music and sound effects is rendered (other sounds at −120 dB, so ducking "
                + "stays as in the mix) and measured over time. Spoken blocks are those inside heard or caption words, "
                + "else where the speech stem is over −70 LUFS. Returns voice, musicUnderSpeech (voice minus music, "
                + "in LU) and musicInGaps as {median, p10, p90, blocks}; speechWindows with the same per window; "
                + "effects per sound-effect item: loudness (loudest momentary LUFS), peakDb, the voice at the same "
                + "moment (voiceDuring LUFS, voicePeakDb) with overVoiceDb and peakOverVoiceDb (the effect minus "
                + "them; a short effect reads low on 400 ms loudness, so read its peak too), voiceP95 within "
                + "nearSeconds with deltaDb, sharedWith (effects playing at once, measured together), onset and peak "
                + "offsets in frames to the nearest cut, beat and word edge; musicBeds per Music layer: ducking false "
                + "(a fixed bed), or duckDb, minGapSeconds, rises (gaps where it comes back up), shortRises (gaps under "
                + "2.5 s), movesPerMinute and pumping (over 4 moves a minute); and each stem's integrated loudness. "
                + "No other verdicts. A job; no levels are changed. jobs status shows its progress and the stem and "
                + "timeline second being rendered; a stem rendered without a curve, or silent although its layers hold "
                + "sound, fails the job with the reason (musicUnderSpeech null otherwise comes with "
                + "musicUnderSpeechReason).",
            parameters: [
                CommandParameter("nearSeconds", .number,
                                 "Width in seconds of the window on each side of every sound effect where the voice is "
                                    + "read (default 1); not a timeline time: the whole timeline is always measured",
                                 range: 0.1...10, cli: .option("near")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "media.sync", .read,
            "Find the time offset between two recordings of the same moment (a camera and a screen recording, or a "
                + "render played inside a screen recording) from their sound, with an audio.sync provider. The job's "
                + "result: time in `to` = time in `media` + offsetSeconds, the correlation (below 0.4: no shared sound) "
                + "and each half of the overlap (steady: no clock drift). With item, also the matching source frame "
                + "of `to` for that clip's in-point.",
            parameters: [
                CommandParameter("media", .string, "Project media ID of the first recording", required: true,
                                 cli: .option("media")),
                CommandParameter("to", .string, "Project media ID of the second recording", required: true,
                                 cli: .option("to")),
                CommandParameter("item", .string, "A timeline item of the first media whose in-point to map",
                                 cli: .option("item")),
                provider,
            ],
            execution: .job),
    ]

    /// Sampling for `media.subjects` and `media.ocr` (P2-H6, P2-H7).
    static var visionParameters: [CommandParameter] {
        [
            mediaMedia,
            CommandParameter("step", .number, "Source seconds between pictures (default 1; at most 3600 pictures)",
                             range: 0.04...3_600, cli: .option("step")),
            CommandParameter("from", .number, "From this source second", range: 0...86_400, cli: .option("from")),
            CommandParameter("to", .number, "Up to this source second", range: 0...86_400, cli: .option("to")),
            provider,
        ]
    }
}
