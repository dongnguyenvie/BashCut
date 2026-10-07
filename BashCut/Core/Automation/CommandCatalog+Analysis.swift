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
            + "review.picture) when review.measure ran for this revision (pictureMeasured). No verdicts. With "
            + "summary: count, total, mean, median, min and max seconds and cuts per minute.",
        parameters: [
            CommandParameter("summary", .boolean, "Add count, length statistics and cuts per minute",
                             cli: .flag("summary"))
        ])

    /// Read-only sound analysis through plugin providers; each runs as a job whose result holds the values.

    static let analysisSpecs: [CommandSpec] = [
        CommandSpec(
            "audio.measure", .read,
            "Measure a media file's sound with an audio.loudness provider: integrated loudness (LUFS), true peak, "
                + "loudness range (LU) and the energy share in the speech band (300-3000 Hz) and the presence band "
                + "(1-4 kHz, where consonants carry words). Under a voice, prefer music with a low presence share and "
                + "loudness range. The job's result holds the values.",
            parameters: [
                CommandParameter("media", .string, "Project media ID", required: true, cli: .option("media")),
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
