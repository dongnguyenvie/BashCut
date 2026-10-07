import BashCutProject
import Foundation

/// Source media as data (P0-A1): a measured record per file, read with the agent's own limits, and cut corrections.
extension CommandCatalog {
    static let mediaListSpec = CommandSpec(
        "media.list", .read,
        "List project media. With analysis, each media also has analysis: measured false, or {measured, key, "
            + "measuredAt, picture, sound, shots at the default cut limit, corrected} from media.analyze, and "
            + "transcript: transcribed false, or the media.transcript overview from media.transcribe.",
        parameters: [
            CommandParameter("analysis", .boolean, "Add what media.analyze measured and media.transcribe heard",
                             cli: .flag("analysis"))
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
