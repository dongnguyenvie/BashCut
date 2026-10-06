import BashCutProject
import Foundation

extension CommandCatalog {
    static let reviewSpec = CommandSpec(
        "review.run", .read,
        "Review the timeline before export. Each issue has a severity (error: spoils the export, warning: hurts "
            + "it, info: a note) and, when one exists, a fix: a command with arguments, or a hint. Errors come first. "
            + "With summary, the result is {issues, summary: {errors, warnings, infos, passed}}; passed means no "
            + "error. Loudness is checked from the last normalized export of this revision, black and frozen picture "
            + "and jump cuts from the last review.measure of this revision. Issues over a stretch carry endFrame. "
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
        "Render the timeline small (two frames a second and both sides of every hard cut on Main, proxies "
            + "allowed) and keep the picture measurement for this revision, so review.run checks black or empty "
            + "picture, frozen picture, long static shots and jump cuts. The job's result has the sample count and "
            + "the picture issues found; measure again after an edit.",
        execution: .job)

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
