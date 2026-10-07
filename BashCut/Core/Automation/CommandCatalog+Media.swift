import BashCutProject
import Foundation

/// Source media as data (P0-A1): a measured record per file, read with the agent's own limits, and cut corrections.
extension CommandCatalog {
    static let mediaListSpec = CommandSpec(
        "media.list", .read,
        "List project media. With analysis, each media also has analysis: measured false, or {measured, key, "
            + "measuredAt, picture, sound, shots at the default cut limit, corrected} from media.analyze, and "
            + "transcript: transcribed false, or the media.transcript overview from media.transcribe. A described media "
            + "has description {shots, describedBy, describedAt}; with analysis, its media.description coverage.",
        parameters: [
            CommandParameter("analysis", .boolean, "Add what media.analyze measured and media.transcribe heard",
                             cli: .flag("analysis"))
        ])

    /// `context.get`, which also reports analysis readiness (P0-A6).
    static let contextSummary =
        "Read the project path, revision, playhead and selection, and a summary of the agent knowledge: active "
            + "lessons, preferences, project facts and the number of proposals; scope lists the timeline items "
            + "attached to your tab's request (edit only those), with the scope guard's mode, a held edit and "
            + "the user's answer to the last one (last); agentPermissions tells what you may do without asking; "
            + "analysis lists running analysis jobs and the media not yet measured (media.analyze), transcribed "
            + "(media.transcribe) or described (media.describe), so a plan does not use defaults where "
            + "measurements are missing."

    /// Every command about source media (P0-A).
    static var sourceMediaSpecs: [CommandSpec] {
        mediaAnalysisSpecs + sourceTranscriptSpecs + mediaDescriptionSpecs + mediaStillsSpecs + [mediaInventorySpec]
    }

    static let mediaInventorySpec = CommandSpec(
        "media.inventory", .read,
        "What the footage holds, from one call (read only; capture facts are read once per file and kept in "
            + ".bashcut/cache/inventory). media [{id, path, folder, kind, seconds, width/height shown and orientation, "
            + "capturedAt and location as the file records them (null when it does not), device, hasAudio, measured "
            + "(media.analyze), transcript {language, speechSeconds, words} or null, description coverage}], folders "
            + "and totals {media, seconds, speechSeconds, languages, measured, transcribed, described, notMeasured, "
            + "notTranscribed, notDescribed (IDs), capturedFrom/To, locations [{latitude, longitude, media}] grouped "
            + "on a locationGrid-degree grid, withoutLocation}. Facts only.",
        parameters: [
            CommandParameter("locationGrid", .number, "Degrees that group places (default 0.001, about 100 m)",
                             range: 0...10, cli: .option("location-grid"))
        ])

    static let mediaMedia = CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media"))

    static let mediaAnalysisSpecs: [CommandSpec] = [
        CommandSpec(
            "media.analyze", .read,
            "Measure source media once and keep the record (by file content, in .bashcut/cache/analysis): file facts "
                + "(codec, size, rotation, frame timing for variable frame rate, colour transfer/primaries/bit depth, "
                + "track lengths), picture samples (luma, spread, change, peak as in review.picture, plus sharpness and "
                + "colourfulness) with every jump searched to its exact frame as a cut candidate, and sound levels "
                + "(RMS per 0.1 s, peak, stereo correlation). Read it with media.analysis. A record that exists is "
                + "reused unless force. The job's result lists each media with its key and whether it was reused.",
            parameters: [
                CommandParameter("media", .string, "Project media ID; every video and audio media by default",
                                 cli: .option("media")),
                CommandParameter("force", .boolean, "Measure again even when a record exists (drops corrections)",
                                 cli: .flag("force")),
                CommandParameter("rate", .number, "Picture samples per second (default 4)", range: 0.5...30,
                                 cli: .option("rate")),
            ],
            execution: .job),
        CommandSpec(
            "media.analysis", .read,
            "Read the media.analyze record of one media without measuring: tech (file facts, variableFrameRate, "
                + "transferKind sdr/pq/hlg/log/unknown, audioMinusVideoSeconds), picture {cuts (score = cutDifference, "
                + "or added), shots with the review.shots fields (index, at/atSeconds, duration/seconds in source "
                + "frames, cutDifference, motion) plus mean luma/spread/sharpness/colourfulness, summary (the "
                + "review.shots statistics, a shot-length histogram and cuts per 10 s)}, sound {floorDb, medianDb, "
                + "loudDb, peakDb, silentShare, active spans over floor + activityDb, activeShare, stereoCorrelation} "
                + "and corrections. The limits are yours: lower minScore to see weaker cuts. No verdicts.",
            parameters: [
                mediaMedia,
                CommandParameter("minScore", .number, "Lowest candidate score read as a cut (default 0.1)",
                                 range: 0...1, cli: .option("min-score")),
                CommandParameter("activityDb", .number, "dB over the sound floor that counts as active (default 10)",
                                 range: 0...80, cli: .option("activity-db")),
                CommandParameter("bridgeSeconds", .number, "Quiet gaps bridged inside an active span (default 0.3)",
                                 range: 0...10, cli: .option("bridge")),
                CommandParameter("samples", .boolean, "Include every picture sample", cli: .flag("samples")),
                CommandParameter("curve", .boolean, "Include the sound level per second (dBFS)", cli: .flag("curve")),
            ]),
        CommandSpec(
            "media.speech-map", .read,
            "Map where an analysed media has sound that may be speech, and the gaps, with the calibration used: the "
                + "media.analyze level windows (broadband RMS per 0.1 s; digital silence counts as quiet and is left "
                + "out) are split into quiet and loud by Otsu's method unless thresholdDb is given. calibration "
                + "{method otsu/given, floorDb, speechDb, separationDb, eta (share of level variance the split "
                + "explains), otsuThresholdDb, thresholdDb, minSeparationDb, separation clear/weak/none/given}. When "
                + "the classes are closer than minSeparationDb (noise, music under the voice) separation is none and "
                + "spans/gaps are null with a reason, instead of made-up silences. Otherwise spans and gaps "
                + "[{start, end, seconds}] in source seconds, speechSeconds, speechShare, gapStats. With a stored "
                + "transcript (media.transcribe), transcript {words, spans, gaps, speechSeconds, levelCoveredByWords, "
                + "wordsCoveredByLevel}. Spans are sound, not proof of speech.",
            parameters: [
                mediaMedia,
                CommandParameter("thresholdDb", .number, "dBFS that counts as sound, instead of calibrating",
                                 range: -120...0, cli: .option("threshold-db")),
                CommandParameter("bridgeSeconds", .number, "Gaps bridged inside a span (default 0.3)", range: 0...10,
                                 cli: .option("bridge")),
                CommandParameter("minSpeechSeconds", .number, "Shortest span kept (default 0.2)", range: 0...10,
                                 cli: .option("min-speech")),
                CommandParameter("minSeparationDb", .number, "Classes closer than this do not separate (default 6)",
                                 range: 0...60, cli: .option("min-separation-db")),
            ]),
        CommandSpec(
            "media.cuts", .edit,
            "Correct the cut list of an analysed media: add cuts or remove candidates at source seconds (a removal "
                + "matches within one sample interval; removing an added cut takes it back). Shots and statistics in "
                + "media.analysis follow. Corrections live in the record and are dropped when the file is measured "
                + "again. Returns the corrected cuts.",
            parameters: [
                mediaMedia,
                CommandParameter("add", .string, "Source seconds to cut at, comma separated", cli: .option("add")),
                CommandParameter("remove", .string, "Source seconds of cuts to drop, comma separated",
                                 cli: .option("remove")),
                CommandParameter("clear", .boolean, "Drop earlier corrections first", cli: .flag("clear")),
            ]),
    ]

    /// Shot facts written by the agent (P0-A4), stored on the media in the project.
    static let mediaDescriptionSpecs: [CommandSpec] = [
        CommandSpec(
            "media.describe", .edit,
            "Store what you saw in a source media, shot by shot, as one undoable edit (it is saved with the project). "
                + "Each shot: start and end in source seconds (shots may not overlap) and at least one fact in the "
                + "closed vocabulary: size ECU/CU/MCU/MS/MWS/WS/EWS/insert, angle eye/high/low/top/dutch/pov/ots, "
                + "move static/pan/tilt/push/pull/track/orbit/handheld/zoom/crane, direction left/right/toward/away/"
                + "none, subjects (up to 12 names), people, onScreenText, confidence 0–1, bestMoment (source "
                + "seconds or null), looked (source seconds of the frames you looked at), note. Unknown fields and "
                + "values are rejected; there is no field for pairings or verdicts. Replaces the description unless "
                + "merge (shots overlapping the new ones are replaced) or clear. Returns rev and coverage.",
            parameters: [
                CommandParameter("shots", .array, "Shots array, or {shots: […]} (CLI: path to shots.json)",
                                 cli: .positionalJSONFile),
                mediaMedia,
                CommandParameter("merge", .boolean, "Keep stored shots that the new ones do not overlap",
                                 cli: .flag("merge")),
                CommandParameter("clear", .boolean, "Remove the description", cli: .flag("clear")),
                baseRevision,
            ]),
        CommandSpec(
            "media.description", .read,
            "Read media descriptions. With media: description {shots, describedBy, describedAt} and coverage {shots, "
                + "describedSeconds, describedShare, and with a media.analyze record measuredShots, coveredShots (half "
                + "or more of the measured shot described) and missing [{index, start, end}]}. Without: each media's "
                + "coverage, describedMedia/totalMedia, measuredShots/coveredShots, missing media IDs and the "
                + "vocabulary.",
            parameters: [
                CommandParameter("media", .string, "Project media ID; every media by default", cli: .option("media"))
            ]),
    ]

    /// Source frames as pictures (P0-A5): by source time, never through the timeline.
    static let mediaStillsSpecs: [CommandSpec] = [
        CommandSpec(
            "media.frames", .read,
            "Read exact source frames of media as PNG files (in .bashcut/cache/media-stills; read them to look): "
                + "at the given source seconds, every N seconds, or count evenly spaced (default 8, each in the middle "
                + "of its part) over from…to (the whole file by default). Every media with a picture by default. "
                + "frames [{path, media, frame (exact source frame index), seconds, width, height}]. With sheet: "
                + "contact sheets of columns × rows cells labelled '<cell> <file> <m:ss.s>' (the colour changes with "
                + "each media), sheets [{path, cells [{cell, media, frame, seconds}]}], so a cell maps back to its "
                + "media and second. With reference (one media): a sheet with a REF row from that media (over "
                + "referenceFrom…referenceTo) above an OURS row, cell for cell. At most 400 frames per call.",
            parameters: [
                CommandParameter("media", .string, "Media IDs, comma separated; every media with a picture by default",
                                 cli: .option("media")),
                CommandParameter("at", .string, "Source seconds, comma separated (one media)", cli: .option("at")),
                CommandParameter("every", .number, "Seconds between frames", range: 0.04...3_600, cli: .option("every")),
                CommandParameter("count", .integer, "Frames per media, evenly spaced (default 8)", minimum: 1,
                                 maximum: 400, cli: .option("count")),
                CommandParameter("from", .number, "From this source second (one media)", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("to", .number, "Up to this source second (one media)", range: 0...86_400,
                                 cli: .option("to")),
                CommandParameter("sheet", .boolean, "Contact sheets instead of one file per frame", cli: .flag("sheet")),
                CommandParameter("columns", .integer, "Cells per row (default 8 portrait, 6 landscape)", minimum: 1,
                                 maximum: 24, cli: .option("columns")),
                CommandParameter("rows", .integer, "Rows per sheet (default 3 portrait, 6 landscape)", minimum: 1,
                                 maximum: 24, cli: .option("rows")),
                CommandParameter("size", .integer, "Long edge of each frame in pixels (default 320 on a sheet, 640)",
                                 minimum: 64, maximum: 4_096, cli: .option("size")),
                CommandParameter("reference", .string, "Media ID of a reference shown as a REF row",
                                 cli: .option("reference")),
                CommandParameter("referenceFrom", .number, "Reference from this source second", range: 0...86_400,
                                 cli: .option("reference-from")),
                CommandParameter("referenceTo", .number, "Reference up to this source second", range: 0...86_400,
                                 cli: .option("reference-to")),
            ]),
        CommandSpec(
            "media.frame", .read,
            "Write one source frame of a media as a PNG at source size (or size on the long edge): at source "
                + "seconds, an exact frame index, or edge first/last (the first frame by default), for chaining, "
                + "transitions or a generation reference. Returns {path, media, frame, seconds, width, height}.",
            parameters: [
                mediaMedia,
                CommandParameter("at", .number, "Source seconds", range: 0...86_400, cli: .option("at")),
                CommandParameter("index", .integer, "Source frame index", minimum: 0, cli: .option("index")),
                CommandParameter("edge", .string, "first or last", choices: ["first", "last"], cli: .option("edge")),
                CommandParameter("size", .integer, "Long edge in pixels; the source size by default", minimum: 16,
                                 maximum: 16_384, cli: .option("size")),
            ]),
        CommandSpec(
            "media.strip", .read,
            "Draw a filmstrip of a source range as one PNG: count frames (default 8) along the top with their time, "
                + "a time ruler, the sound level (−60…0 dBFS per 0.1 s, from the media.analyze record or measured "
                + "now), the media.speech-map gaps shaded (left out when speech and floor do not separate), and the "
                + "stored transcript's words at their times. Returns {path, width, height, from, to, frames, levels "
                + "(analysis, measured or null), gaps {shown, count or reason}, words}.",
            parameters: [
                mediaMedia,
                CommandParameter("from", .number, "From this source second (default 0)", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("to", .number, "Up to this source second (default the end)", range: 0...86_400,
                                 cli: .option("to")),
                CommandParameter("count", .integer, "Frames along the top (default 8)", minimum: 1, maximum: 24,
                                 cli: .option("count")),
                CommandParameter("width", .integer, "Image width in pixels (default 1600)", minimum: 400,
                                 maximum: 8_192, cli: .option("width")),
            ]),
    ]

    /// `captions.generate --fresh`.
    static let freshTranscript = CommandParameter(
        "fresh", .boolean, "Transcribe again instead of using the media's stored transcript", cli: .flag("fresh"))

    /// What was said in source media (P0-A2), kept by file content and read in source seconds.
    static let sourceTranscriptSpecs: [CommandSpec] = [
        CommandSpec(
            "media.transcribe", .read,
            "Transcribe whole source media once with a captions.transcribe provider and keep the transcript (by file "
                + "content, in .bashcut/cache/transcripts), without placing anything on the timeline. Read it with "
                + "media.transcript; captions.generate places captions from it without transcribing again, and "
                + "transcript.words --heard maps its words through the clips. A transcript in the project's content "
                + "language (by the given provider) is reused unless force. The job's result lists each media with "
                + "status transcribed, reused or failed and its overview.",
            parameters: [
                CommandParameter("media", .string, "Project media ID; every video and audio media by default",
                                 cli: .option("media")),
                CommandParameter("force", .boolean, "Transcribe again even when a transcript exists",
                                 cli: .flag("force")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "media.transcript", .read,
            "Read the stored transcript of one media in its own seconds: language, provider, transcribedAt, "
                + "speechSeconds, firstSpeech/lastSpeech, precision (wordTimes provider or none, and whether words carry "
                + "confidence, speakers, events, noSpeechProb), then as words: wordList [{index, text, start, end, "
                + "gapBefore, confidence?, speaker?, event?, noSpeechProb?}]; phrases (default): phraseList [{index, "
                + "start, end, seconds, text, words, confidence (mean), gapBefore}]; json: both; text: one line per "
                + "phrase (#index start–end seconds | text; print it with --format text). from/to keep what overlaps.",
            parameters: [
                mediaMedia,
                CommandParameter("as", .string, "phrases (default), words, json or text",
                                 choices: SourceTranscript.Format.allCases.map(\.rawValue), cli: .option("as")),
                CommandParameter("from", .number, "Only from this source second", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("to", .number, "Only up to this source second", range: 0...86_400, cli: .option("to")),
            ]),
    ]
}
