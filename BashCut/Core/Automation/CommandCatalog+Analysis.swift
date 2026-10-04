import BashCutProject
import Foundation

extension CommandCatalog {
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
