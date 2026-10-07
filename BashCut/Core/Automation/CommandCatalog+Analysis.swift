import BashCutProject
import Foundation

extension CommandCatalog {
    static let reviewSpec = CommandSpec(
        "review.run", .read,
        "Review the timeline before export. Each issue has a severity (error: spoils the export, warning: hurts "
            + "it, info: a note) and, when one exists, a fix: a command with arguments, or a hint. Errors come first. "
            + "With summary, the result is {issues, summary: {errors, warnings, infos, passed}}; passed means no "
            + "error. Loudness is checked from the last normalized export of this revision, black and frozen picture, "
            + "jump cuts and plugin checks from the last review.measure of this revision. Issues over a stretch carry endFrame. "
            + "Pacing (shot length, still picture) follows the project's review object (minShotSeconds, "
            + "maxShotSeconds, maxStillSeconds) when set.",
        parameters: [
            CommandParameter("minSeverity", .string, "Leave out issues less severe than this",
                             choices: ReviewSeverity.allCases.map(\.rawValue), cli: .option("min-severity")),
            CommandParameter("summary", .boolean, "Wrap the issues with counts and a pass flag",
                             cli: .flag("summary")),
        ])

    static let reviewMeasureSpec = CommandSpec(
        "review.measure", .read,
        "Run the measured review for this revision and keep it, so review.run includes it: render the timeline "
            + "small (two frames a second and both sides of every hard cut on Main, proxies allowed) for black or "
            + "empty picture, frozen picture, long static shots and jump cuts, and run every enabled plugin "
            + "review.check side by side (each at most 30 s; a failing or slow check becomes an info issue). Plugin "
            + "issues carry source (the plugin ID) and IDs prefixed with the provider. A project turns checks off "
            + "with review.disabledChecks (plugin or provider IDs; timeline apply setProjectProperties). The job's "
            + "result has the sample count, the plugin checks that ran and the measured issues; measure again after "
            + "an edit.",
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
            + "set, gapBefore (frames since the previous shot), transitionIn {kind, duration} or the picture "
            + "cutDifference across a hard cut, and motion {mean, peak, samples} (fractions of full scale, see "
            + "review.picture) when review.measure ran for this revision (pictureMeasured), described (the "
            + "media.describe facts of the source shot it plays), cameraMove [{property, from, to, perSecond, unit, "
            + "ease}] from its keyframes, and cut (into it): sameMedia, sameSetup (same media, overlapping or "
            + "adjacent source), sourceGapSeconds, size/move/direction {from, to} when described. No verdicts. With "
            + "summary: count, total, mean, median, min and max seconds and cuts per minute; rhythm {overall, "
            + "sections [per section marker]} with mean, median, cv, cutsPerMinute, mode (the most common length "
            + "bin and its share) and, given runLength and maxCV, lowVarianceRuns; runs of shots with the same "
            + "described size and move; shares of each size, move and direction. With media: the same for a source "
            + "file's measured shots (media.analyze) and its descriptions.",
        parameters: [
            CommandParameter("summary", .boolean, "Add statistics, rhythm, runs and shares", cli: .flag("summary")),
            CommandParameter("media", .string, "Read a source file's measured shots instead of Main",
                             cli: .option("media")),
            CommandParameter("minScore", .number, "With media: lowest cut score (default 0.1)", range: 0...1,
                             cli: .option("min-score")),
            CommandParameter("runLength", .integer, "Shots in a low-variance run (with maxCV)", minimum: 2,
                             maximum: 100, cli: .option("run-length")),
            CommandParameter("maxCV", .number, "Largest length variation (deviation over mean) in such a run",
                             range: 0...10, cli: .option("max-cv")),
        ])

    /// The cuts on Main and their timing against beats and words (P0-B2).
    static let reviewCutSpecs: [CommandSpec] = [
        CommandSpec(
            "review.cuts", .read,
            "Read every cut on Main: index, frame/seconds, from/to item IDs, kind (hard, or the transition's kind with "
                + "transitionFrames/Seconds and easing), gapFrames when there is a gap, framingBefore/After {zoom, pan, "
                + "tilt} (keyframes included) and sameFraming (same media and the same framing on both sides); counts "
                + "per kind, runs of the same kind and how many cuts keep the framing. No verdicts."),
        CommandSpec(
            "review.sync", .read,
            "Time events against the beat grid and the spoken words: per event (cuts on Main by default; text items "
                + "and sfx items on request) the nearest beat and the nearest word edge (start or end, its text, "
                + "whether the event falls inside the word) with offsetFrames and offsetMs (positive = after it), and "
                + "for beats and words the distribution: count, mean, median, p10, p90 and counts per offset from −6 "
                + "to +6 frames. Words are the stored transcripts heard through the clips (media.transcribe), else "
                + "the caption words. With rendered: rendered {windows [{at, lagMs, correlation}], driftMsPerMinute, "
                + "lagStartMs, lagEndMs} from matching the last export's sound to the timeline's mix every 10 s "
                + "(positive lag = the render is later); the export must show this revision.",
            parameters: [
                CommandParameter("events", .string, "cuts, text, sfx (comma separated; default cuts)",
                                 cli: .option("events")),
                CommandParameter("rendered", .boolean, "Also measure the last export's timing against the timeline",
                                 cli: .flag("rendered")),
            ]),
    ]

    static let uiFrameSpec = CommandSpec(
        "ui.frame", .read,
        "Render the viewer's picture at a timeline frame (the playhead by default) to a PNG, like attaching the "
            + "viewer frame in Ask; returns its path. Read the file to look at the edit. Keeps the ten newest. width "
            + "renders it that many pixels wide (phone: 390, about a phone screen, to judge text at the size viewers "
            + "see it); otherwise up to 1280 on the long edge.",
        parameters: [
            CommandParameter("frame", .integer, "Timeline frame; the playhead by default", minimum: 0, cli: .positional),
            CommandParameter("width", .integer, "Width in pixels", minimum: 64, maximum: 4_096, cli: .option("width")),
            CommandParameter("phone", .boolean, "390 pixels wide", cli: .flag("phone")),
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
    static let platformsListSpec = CommandSpec(
        "platforms.list", .read,
        "Read the platform facts review uses: per platform (TikTok, Reels, Shorts, YouTube) shape, maxSeconds, "
            + "targetLUFS, maxTruePeakDbTP and safeArea (zones the app covers, as fractions), with the project's "
            + "review.platform overrides applied, whether it is one of the project's outputs and whether it was "
            + "overridden; layout: the zones text is checked against (the strictest of the outputs of the frame's "
            + "shape, null when none); targets: each output preset's loudness target (output.targets, else the "
            + "platform's).")

    /// Hook and close as facts (#467, P0-B11).
    static let reviewHookSpec = CommandSpec(
        "review.hook", .read,
        "Read how the edit opens and closes, as facts: opening {hookSeconds (the project's review.hookSeconds or "
            + "null), firstWords {frame, seconds, text} (heard or caption words), firstSpeechItem, firstTitle and "
            + "firstCaption {frame, seconds, item, text, holdSeconds}, firstCut, described {subjects and sizes [{name, "
            + "firstFrame, firstSeconds, onScreenSeconds}] from media.describe}, firstFrame {luma, mid, inkShare (pixels "
            + "text and overlay layers change)}}, close {duration, lastWords, lastCut, lastTitle with its hold, bounds "
            + "and edges}, and the platform zones. No verdict about what is early enough; the review's hook check runs "
            + "only when the project sets review.hookSeconds.")

    static let reviewLayoutSpec = CommandSpec(
        "review.layout", .read,
        "Read where text sits as the renderer lays it out: per visible text item id, track, trackRole, at/end, text, "
            + "preset, lines, longestLineChars, fontPixels and fontShare (of the frame's short side), bounds (pixels "
            + "from the top-left) and edges (distance to each frame edge as a share of that dimension, negative "
            + "outside), keyframed when keyframes move it (not followed); holdSeconds, words and wordsPerSecond; "
            + "speech {onsetOffsetFrames (from the nearest word start), narrationShare (of its time with words "
            + "spoken)} from the heard or caption words; captionOverlap {item, ratio of its box} for titles; "
            + "templateRepeats (items with its preset on its layer); faceOverlap null (needs a vision.faces "
            + "provider; null means unknown). With contrast: contrast {ratio (WCAG, 1–21) of the mean, lightRatio and "
            + "darkRatio (the light and dark parts of the text, such as fill and outline), textLuminance, "
            + "backgroundLuminance, textPixels} measured on the frame with and without text (at frame, or each "
            + "item's middle). Also the frame size, the platform whose zones apply (safeArea, minTextSize), density "
            + "(titles and captions per minute) and, at a frame, pictures on screen with their scale and coverage. "
            + "No verdicts.",
        parameters: [
            CommandParameter("frame", .integer, "Only text on screen at this timeline frame", minimum: 0,
                             cli: .option("frame")),
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
            "How a music file's energy moves, with an audio.energy provider: every step seconds levelDb, onset "
                + "(density) and fullness (share of octave bands near the loudest), and candidates [{kind lift, drop "
                + "or breath, seconds, magnitude dB, beatSeconds (snapped), timeline [{item, frame}]}] ranked by size, "
                + "count per kind. Pointers to listen to, not cut points. A job.",
            parameters: [
                mediaMedia,
                CommandParameter("count", .integer, "Candidates per kind (default 6)", minimum: 1, maximum: 50,
                                 cli: .option("count")),
                CommandParameter("windowSeconds", .number, "Seconds compared before and after (default 2)",
                                 range: 0.5...30, cli: .option("window")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "audio.mix-measure", .read,
            "Read the mix by role without exporting: one stem each for speech (dialogue and voiceover layers and the "
                + "sound of video clips), music and sound effects is rendered (other sounds at −120 dB, so ducking "
                + "stays as in the mix) and measured over time. Spoken blocks are those inside heard or caption words, "
                + "else where the speech stem is over −70 LUFS. Returns voice, musicUnderSpeech (voice minus music, "
                + "in LU) and musicInGaps as {median, p10, p90, blocks}; speechWindows with the same per window; "
                + "effects per sound-effect item: loudness (loudest momentary LUFS), peakDb, voiceP95 within "
                + "nearSeconds, deltaDb, masked (under that voice level), onset and peak offsets in frames to the "
                + "nearest cut, beat and word edge; and each stem's integrated loudness. A job; no levels are changed.",
            parameters: [
                CommandParameter("nearSeconds", .number, "Seconds around an effect read for the voice (default 1)",
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
}
