import BashCutProject
import Foundation

/// Source media as data (P0-A1): a measured record per file, read with the agent's own limits, and cut corrections.
extension CommandCatalog {
    static let mediaListSpec = CommandSpec(
        "media.list", .read,
        "List project media. With analysis, each media also has analysis: measured false, or {measured, key, "
            + "measuredAt, picture, sound, shots at the default cut limit, corrected} from media.analyze.",
        parameters: [
            CommandParameter("analysis", .boolean, "Add what media.analyze measured for each media",
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
}
