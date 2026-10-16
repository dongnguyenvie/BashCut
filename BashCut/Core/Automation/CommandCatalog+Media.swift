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
            + "measurements are missing; plan summarises the brief (goal, outputs, length) and the edit plan (mode, "
            + "stage, section/shot/beat counts, frozen sections, recipe, promise, checks count, requiredStages, naStages); "
            + "workflow has the gates, the checkpoint, checklist (each stage's status, audit verdicts, open points; "
            + "run checklist has it all) and next {stage, skill, skillRead, recipe when unread}: the one skill to read "
            + "now; recentFailures lists your session's failed requests "
            + "of the last 15 minutes (method, code, category, message) and repeated, how many in a row at the newest "
            + "end share a method and category: stop and rethink after repeated ones."

    /// Every command about source media (P0-A).
    static var sourceMediaSpecs: [CommandSpec] {
        mediaAnalysisSpecs + sourceTranscriptSpecs + mediaDescriptionSpecs + mediaStillsSpecs
            + [mediaInventorySpec, mediaDigestSpec, speechRateSpec, narrationWindowsSpec, voiceSpeakSpec, voiceLinesSpec,
               voicePlaceSpec] + voiceCheckSpecs
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

    static let mediaDigestSpec = CommandSpec(
        "media.digest", .read,
        "Footage facts in one read. A header (seconds, size, speech share, counts), "
            + "then in time order the described shots (`shot FROM-TO size angle move | subjects | note | best T`, from "
            + "media describe), each transcript phrase (`START text`, with `[again T]` when a phrase within 120 s says "
            + "nearly the same words: a possible retake) and the measured cuts no description covers. Whether a line "
            + "is a retake or a cue to the camera is yours to judge. Reads stored analysis, descriptions and "
            + "transcripts only (run media analyze, media transcribe and media describe first). The whole project's "
            + "digest is also written to analysis/digest.json. as json returns {media, name, seconds, size, cuts, "
            + "speechSeconds, shots [{from, to, size, angle, move, subjects, note, best}], phrases [[start, end, text, "
            + "againAt?]]}.",
        parameters: [
            CommandParameter("media", .string, "Only this media", cli: .option("media")),
            CommandParameter("from", .number, "From this source second", range: 0...1_000_000, cli: .option("from")),
            CommandParameter("to", .number, "To this source second", range: 0...1_000_000, cli: .option("to")),
            CommandParameter("as", .string, "text (default) or json", choices: ["text", "json"], cli: .option("as")),
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
                + "reused unless force. Ask right after import: media still being converted are measured when the conversion lands. "
                + "The job's result lists each media with its key and whether it was reused.",
            parameters: [
                CommandParameter("media", .string, "Project media ID, or several as A,B; every video and audio media by default",
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
                + "Each shot: start and end in source seconds (shots may not overlap) and at least one fact: size, "
                + "angle, move, direction (open labels; suggested: size ECU/CU/MCU/MS/MWS/WS/EWS/insert, angle "
                + "eye/high/low/top/dutch/pov/ots, move static/pan/tilt/push/pull/track/orbit/handheld/zoom/crane, "
                + "direction left/right/toward/away/none), subjects (up to 12 names), tags, people, onScreenText, "
                + "confidence 0–1, bestMoment (source seconds or null), looked (source seconds of the frames you "
                + "looked at), note; any other field is kept as given. Replaces the description unless "
                + "merge (shots overlapping the new ones are replaced) or clear. Obvious slips are repaired and listed "
                + "in adjusted: numbers as text (\"659 s\"), subjects as one comma-separated string, labels and notes "
                + "over their length, a best moment or looked frames outside the shot, a shot running into the next "
                + "(it ends where the next starts); what cannot be repaired is reported for every shot at once. "
                + "Returns rev, coverage and adjusted.",
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
                + "referenceFrom…referenceTo) above an OURS row, cell for cell. At most 400 frames per call. With "
                + "file: frames of a video not in the project (a stock or library candidate), at or count over the "
                + "whole file, frames [{path, file, frame, seconds, width, height}].",
            parameters: [
                CommandParameter("media", .string, "Media IDs, comma separated; every media with a picture by default",
                                 cli: .option("media")),
                CommandParameter("file", .string, "Absolute path of a video not in the project, instead of media",
                                 cli: .option("file")),
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

    /// How fast people and voices speak (P0-C2).
    static let speechRateSpec = CommandSpec(
        "speech.rate", .read,
        "Measure speaking rate in the content language's unit (syllables for Vietnamese, characters for Chinese, "
            + "Japanese and Korean, else words): per transcribed media (media.transcribe) and speaker, each phrase's "
            + "rate over its own length as p10/p50/p90, overall (all units over all phrase time) and articulation (over "
            + "the time words sound); and voices: the rates measured on synthesized takes (voice speak), per voice and "
            + "language, with sample count and p10/p50/p90. No normal rate is assumed.",
        parameters: [
            CommandParameter("media", .string, "Project media ID; every transcribed media by default",
                             cli: .option("media")),
            CommandParameter("unit", .string, "Count in this unit instead", choices: SpeechUnits.Unit.allCases.map(\.rawValue),
                             cli: .option("unit")),
            CommandParameter("voice", .string, "Only this voice (provider/voice)", cli: .option("voice")),
        ])

    /// Where narration could go (P0-C3).
    static let narrationWindowsSpec = CommandSpec(
        "narration.windows", .read,
        "List stretches of at least minSeconds with no spoken word (heard or caption words) and no voiceover item: "
            + "at/end frames and seconds, anchors {afterWord (the last word before it), firstCut, firstBeat, section, "
            + "sectionStartsInside}, covered {music, footage} (shares 0–1 of the window), the shots on Main under "
            + "it with their described facts, and with rate (units per second, in the content language's unit) a "
            + "budget of units that fit. With levels, the mix is rendered once (no export) and each window gets its "
            + "mixLoudness {median, p10, p90}. No length or rate is assumed.",
        parameters: [
            CommandParameter("minSeconds", .number, "Shortest window listed", required: true, range: 0.1...600,
                             cli: .option("min-seconds")),
            CommandParameter("rate", .number, "Units per second for the text budget", range: 0.1...50, cli: .option("rate")),
            CommandParameter("levels", .boolean, "Render the mix to add each window's loudness", cli: .flag("levels")),
        ])

    /// Voiceover takes with their measured facts (P0-C4, C6, C7).
    static let voiceSpeakSpec = CommandSpec(
        "voice.speak", .edit,
        "Synthesize voice takes and measure them: per take index, path, projectPath, seconds, units (syllables, "
            + "words or characters for the content language), unitsPerSecond over its sound, leadingSilence, "
            + "trailingSilence, pauses and the provider's score when it gives one; the rates are kept per voice "
            + "(speech rate). Every take file is kept: pick one yourself and put it on the timeline with voice place. "
            + "With choose, take N goes on the Voiceover track at once (the rest are removed); with replace, the take "
            + "(choose, default 1) goes into that item, keeping its place, and its captions are timed again. The item "
            + "keeps voice {text, language, provider, voice}.",
        parameters: [
            CommandParameter("text", .string, "Voiceover text in the project content language (with replace, "
                             + "the item's voice text by default)", sensitive: true, cli: .positional),
            CommandParameter("takes", .integer, "Number of takes to generate; capped to the provider's maxTakes "
                             + "(requestedTakes in the answer when it gave fewer)", default: .integer(3), minimum: 1,
                             maximum: 8, cli: .option("takes")),
            provider,
            CommandParameter("voice", .string, "Voice for this request: a preset (voice or provider/voice) or a saved "
                             + "clone ID (clone-…, sent to a provider that clones with its saved consent); the project's "
                             + "voice by default", cli: .option("voice")),
            CommandParameter("choose", .integer, "Put this take on the timeline (1 = first)", minimum: 1, maximum: 8,
                             cli: .option("choose")),
            CommandParameter("atFrame", .integer, "With choose: timeline frame; defaults to the playhead", minimum: 0,
                             cli: .option("at-frame")),
            CommandParameter("replace", .string, "Voiceover item to put the take into, keeping its place",
                             cli: .option("replace")),
            CommandParameter("cloneConsent", .boolean, "The user agreed to clone the voice set in the plugin's "
                             + "options; providers that clone refuse without it", cli: .flag("clone-consent")),
        ] + paidRequestParameters,
        execution: .job)

    /// Every line of a script voiced and checked in one job: what `plan.cut.voiceover` plays.
    static let voiceLinesSpec = CommandSpec(
        "voice.lines", .edit,
        "Voice every line of a script in one job: per line, takes are synthesized and kept (like voice speak), each "
            + "is transcribed and diffed against its text, and with minSimilarity a line whose takes all fall below "
            + "it is voiced again (retries). Lines default to plan.cut.voiceover; a line that already has a kept take "
            + "at or above minSimilarity is not voiced again unless force. Nothing goes on the timeline: plan apply "
            + "plays each line's best kept take (or the take its entry names), with captions timed by its words. "
            + "Returns per line id, status (made, kept or failed), best {projectPath, similarity, seconds, "
            + "unitsPerSecond}, takes (how many were made) and unmatched words of the best take when it is under 1.",
        parameters: [
            CommandParameter("lines", .array, "Lines [{id, text}] (CLI: path to a JSON file); plan.cut.voiceover when "
                             + "omitted", cli: .positionalJSONFile),
            CommandParameter("takes", .integer, "Takes per line per try", default: .integer(2), minimum: 1, maximum: 8,
                             cli: .option("takes")),
            CommandParameter("minSimilarity", .number, "A take passes at this similarity; lines with none passing are "
                             + "voiced again", range: 0...1, cli: .option("min-similarity")),
            CommandParameter("retries", .integer, "Extra tries for a line with no passing take", default: .integer(1),
                             minimum: 0, maximum: 3, cli: .option("retries")),
            CommandParameter("only", .string, "Comma-separated line IDs to voice", cli: .option("only")),
            CommandParameter("force", .boolean, "Voice lines that already have a passing kept take", default: .bool(false),
                             cli: .flag("force")),
            provider,
            CommandParameter("cloneConsent", .boolean, "The user agreed to clone the voice set in the plugin's "
                             + "options; providers that clone refuse without it", cli: .flag("clone-consent")),
        ] + paidRequestParameters,
        execution: .job)

    /// A kept take on the timeline (flexibility audit D4).
    static let voicePlaceSpec = CommandSpec(
        "voice.place", .edit,
        "Put a take voice speak kept on the Voiceover track with its voice facts and provenance: at a frame (the "
            + "playhead by default), or into a voiceover item, keeping its place, with its captions timed again from "
            + "the new take.",
        parameters: [
            CommandParameter("take", .string, "The take's path or projectPath from voice speak", required: true,
                             cli: .positional),
            CommandParameter("atFrame", .integer, "Timeline frame; defaults to the playhead", minimum: 0,
                             cli: .option("at-frame")),
            CommandParameter("replace", .string, "Voiceover item to put the take into", cli: .option("replace")),
        ])

    /// Voiceover checks and script captions (P0-C5, P0-C9).
    static let voiceCheckSpecs: [CommandSpec] = [
        CommandSpec(
            "voice.check", .read,
            "Check what a voiceover take says against the text it should say: the take (a voiceover item, or a media) "
                + "is transcribed (or its stored transcript reused) and diffed word by word. Returns similarity (matched "
                + "words over the longer word count), words [{text, heard, kind match|substituted|missing, start, end}], "
                + "unmatched, extra (heard but not in the text) and, only with minSimilarity, passed. The text defaults "
                + "to the item's voice.text. With items (or all), several voiceover items in one job: checks [{item, "
                + "similarity, unmatched, passed}] without the word lists. A job.",
            parameters: [
                CommandParameter("item", .string, "Voiceover item ID", cli: .option("item")),
                CommandParameter("items", .string, "Comma-separated voiceover item IDs, or all (every item with voice text)",
                                 cli: .option("items")),
                CommandParameter("media", .string, "Media ID instead of an item", cli: .option("media")),
                CommandParameter("text", .string, "The text the take should say", sensitive: true, cli: .option("text")),
                CommandParameter("minSimilarity", .number, "Report passed against this similarity", range: 0...1,
                                 cli: .option("min-similarity")),
                provider,
            ],
            execution: .job),
        CommandSpec(
            "voice.fit", .edit,
            "Change a voiceover item's speed (pitch kept) so it lasts frames, or ends at toFrame, as one undoable edit, "
                + "when the needed speed is within minRatio…maxRatio; otherwise nothing changes and the error gives the "
                + "speed it would need. Returns speed, frames and slackFrames. No default bounds.",
            parameters: [
                CommandParameter("item", .string, "Voiceover item ID", required: true, cli: .option("item")),
                CommandParameter("frames", .integer, "Length to fill, in timeline frames", minimum: 1, cli: .option("frames")),
                CommandParameter("toFrame", .integer, "Timeline frame to end at", minimum: 1, cli: .option("to-frame")),
                CommandParameter("minRatio", .number, "Slowest speed allowed (1 = as recorded)", required: true,
                                 range: 0.1...16, cli: .option("min-ratio")),
                CommandParameter("maxRatio", .number, "Fastest speed allowed", required: true, range: 0.1...16,
                                 cli: .option("max-ratio")),
                baseRevision,
            ]),
        CommandSpec(
            "captions.group", .edit,
            "Re-cut captions from word groups you choose, as one undoable edit: groups is a list of runs of word "
                + "indices (from transcript words, or with source heard from transcript words --heard), each becoming "
                + "one caption from its first word's start to its last word's end with its words timed; the captions "
                + "those words fall in are replaced (their style and plan apply marks kept). Rule mode instead (maxChars, maxSeconds and "
                + "breakGapSeconds, all required; from/to limit it) joins words greedily and, unless breakAtCuts is false, "
                + "never across a cut between clips on Main. The cues remember how they were grouped, so a later plan "
                + "apply that rebuilds the captions groups them the same way. Returns rev and facts: cues "
                + "[{frames, seconds, chars, cps, text}], gaps and overlaps between cues in frames. No default grouping.",
            parameters: [
                CommandParameter("groups", .array, "Runs of word indices (CLI: path to groups.json)", cli: .positionalJSONFile),
                CommandParameter("source", .string, "captions (default) or heard", choices: ["captions", "heard"],
                                 cli: .option("source")),
                CommandParameter("maxChars", .integer, "Rule mode: longest caption in characters", minimum: 1, maximum: 500,
                                 cli: .option("max-chars")),
                CommandParameter("maxSeconds", .number, "Rule mode: longest caption in seconds", range: 0.1...60,
                                 cli: .option("max-seconds")),
                CommandParameter("breakGapSeconds", .number, "Rule mode: a pause this long starts a caption",
                                 range: 0...10, cli: .option("break-gap")),
                CommandParameter("breakAtCuts", .boolean, "Rule mode: start a caption at each cut between clips (default true)",
                                 cli: .option("break-at-cuts")),
                CommandParameter("from", .integer, "Rule mode: from this timeline frame", minimum: 0, cli: .option("from")),
                CommandParameter("to", .integer, "Rule mode: up to this timeline frame", minimum: 0, cli: .option("to")),
                baseRevision,
            ]),
        CommandSpec(
            "captions.align", .edit,
            "Make captions whose text is the script and whose times come from the speech: each non-empty line of text "
                + "becomes a cue, timed by matching the script's words to the media's words (its stored transcript, or "
                + "a new transcription), placed through the clips that play the media as one undoable edit. With "
                + "replace, captions of that media in the aligned stretch are replaced. With aligner, a captions.align "
                + "provider times the words instead of the transcript. Returns cues, score (matched "
                + "words over the longer count) and unmatched words with their times. A job.",
            parameters: [
                CommandParameter("media", .string, "Media ID whose speech times the script", required: true,
                                 cli: .option("media")),
                CommandParameter("text", .string, "The script, one cue per line", required: true, sensitive: true,
                                 cli: .option("text")),
                CommandParameter("replace", .boolean, "Replace that media's captions in the stretch", cli: .flag("replace")),
                provider,
                CommandParameter("aligner", .string, "A captions.align provider to time the words instead of the "
                                 + "transcript", cli: .option("aligner")),
            ],
            execution: .job),
    ]

    /// `captions.generate --fresh`.
    static let freshTranscript = CommandParameter(
        "fresh", .boolean, "Transcribe again instead of using the media's stored transcript", cli: .flag("fresh"))

    /// What was said in source media (P0-A2), kept by file content and read in source seconds.
    static let sourceTranscriptSpecs: [CommandSpec] = [
        CommandSpec(
            "media.transcribe", .read,
            "Transcribe whole source media once and keep the transcript. A captions.transcribe provider makes it, stored by "
                + "file content in .bashcut/cache/transcripts; nothing is placed on the timeline. Read it with "
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
            "Read the stored transcript of one media in its own seconds (word times kept out of the silences "
                + "media.analyze measured, as every command reads them; wordsKeptOutOfSilences counts the words moved), "
                + "with words and phrases counted: language, provider, transcribedAt, "
                + "speechSeconds, firstSpeech/lastSpeech, precision (wordTimes provider or none, and whether words carry "
                + "confidence, speakers, events, noSpeechProb, avgLogprob, compressionRatio), then as words: wordList "
                + "[{index, text, start, end, gapBefore, confidence?, speaker?, event?, noSpeechProb?, avgLogprob?, "
                + "compressionRatio?}]; phrases (default): phraseList [{index, "
                + "start, end, seconds, text, words, confidence (mean), gapBefore}]; json: both; text: one line per "
                + "phrase (#index start–end seconds | text; print it with --format text). from/to keep what overlaps; "
                + "ranges reads several windows in one call: text joins them under \"== A–B\" lines, other formats "
                + "return {media, ranges: [one result per window]}.",
            parameters: [
                mediaMedia,
                CommandParameter("as", .string, "phrases (default), words, json or text",
                                 choices: SourceTranscript.Format.allCases.map(\.rawValue), cli: .option("as")),
                CommandParameter("from", .number, "Only from this source second", range: 0...86_400,
                                 cli: .option("from")),
                CommandParameter("to", .number, "Only up to this source second", range: 0...86_400, cli: .option("to")),
                CommandParameter("ranges", .string, "Several windows instead of from/to: A:B,C:D in source seconds",
                                 cli: .option("ranges")),
            ]),
    ]
}
