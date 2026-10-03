import BashCutProject

extension CommandCatalog {
    /// Clip-level edits that have their own Inspector controls.
    static let clipSpecs: [CommandSpec] = [
        CommandSpec(
            "clip.speed", .edit,
            "Change a clip's constant speed like Inspector › Speed. By default the clip keeps its source and its length "
                + "changes (2× halves it), moving later clips on its layer; with keepDuration it keeps its length and uses "
                + "more or less source. Linked picture and sound change together. A clip is shortened to fit its source even "
                + "with keepDuration; the result then has shortened: true.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("speed", .number, "Speed, for example 0.5, 1.5 or 2", required: true,
                                 range: Project.speedRange, cli: .option("speed")),
                CommandParameter("keepDuration", .boolean, "Keep the clip's length instead", default: .bool(false),
                                 cli: .flag("keep-duration")),
                CommandParameter("preservePitch", .boolean, "Keep the voice pitch (on by default)",
                                 cli: .option("preserve-pitch")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.speed-curve", .edit,
            "Give a clip a speed ramp (CapCut Curve) like Inspector › Speed › Curve: a preset ("
                + SpeedCurve.presets.map(\.id).joined(separator: ", ") + ", or none to remove it) or points "
                + "[[t, speed], …] with t from 0 (clip start) to 1 (clip end). The clip keeps its source and its length "
                + "follows the average speed unless keepDuration (still shortened to fit its source, reported as shortened: "
                + "true); linked sound follows; one undo step.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("preset", .string, "Preset name, or none",
                                 choices: SpeedCurve.presets.map(\.id) + ["none"], cli: .option("preset")),
                CommandParameter("points", .string, "Custom points as JSON, e.g. [[0,1],[0.5,3],[1,1]]",
                                 cli: .option("points")),
                CommandParameter("keepDuration", .boolean, "Keep the clip's length instead", default: .bool(false),
                                 cli: .flag("keep-duration")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.reverse", .edit,
            "Play a video clip backwards (with its linked sound): renders a reversed copy of the source it uses into "
                + "the project's reversed/ folder and points the clip at it. Reversing again restores the original.",
            parameters: [CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional)],
            execution: .job),
    ]
}
