import BashCutProject

extension CommandCatalog {
    private static let motionPresets: String = MotionPreset.all.map(\.id).joined(separator: ", ")
    private static let eases: String = ItemMotion.Ease.allCases.map(\.rawValue).joined(separator: ", ")
    private static let motionSummary: String =
        "Animate a clip, image or text over its length (Inspector › Animation): a preset (\(motionPresets); none "
        + "removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with "
        + "frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume "
        + "(dB, like volumeDb; the only one on audio items, none on text); ease: \(eases) (default inOut). Keys "
        + "replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns "
        + "move; presets are for pictures and text."

    /// Caption import (generation is with the plugin capabilities).
    static let captionSpecs: [CommandSpec] = [
        CommandSpec(
            "captions.import", .edit, "Import UTF-8 SubRip captions as one undoable edit.",
            parameters: [
                CommandParameter("text", .string, "SubRip text (CLI: path to a .srt file)", required: true,
                                 cli: .positionalTextFile(maximumBytes: SubRip.maximumBytes)),
                baseRevision,
                CommandParameter("replace", .boolean, "Replace existing captions", default: .bool(false),
                                 cli: .flag("replace")),
            ]),
    ]

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
            "clip.motion", .edit,
            motionSummary,
            parameters: [
                CommandParameter("item", .string, "Item ID; the selection by default", cli: .positional),
                CommandParameter("preset", .string, "Preset name, or none",
                                 choices: MotionPreset.all.map(\.id) + ["none"], cli: .option("preset")),
                CommandParameter("keyframes", .string, "Keyframes as JSON, replacing the item's animation",
                                 cli: .option("keyframes")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.keyframe", .edit,
            "Set one keyframe like the Inspector's controls with keyframes on: property at a timeline frame (the "
                + "playhead by default) to value (its current value when omitted); remove deletes that key. Without "
                + "property, keys every picture property at its current value (the Inspector's Keyframe at playhead); "
                + "on an audio item, its volume. Volume (dB) works on audio items and clips with sound.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selection by default", cli: .positional),
                CommandParameter("property", .string, "Property; all of them by default",
                                 choices: ItemMotion.ranges.keys.sorted(), cli: .option("property")),
                CommandParameter("value", .number, "Value", cli: .option("value")),
                CommandParameter("atFrame", .integer, "Timeline frame inside the item; the playhead by default",
                                 minimum: 0, cli: .option("at-frame")),
                CommandParameter("ease", .string, "Change to the next key", choices: ItemMotion.Ease.allCases.map(\.rawValue),
                                 cli: .option("ease")),
                CommandParameter("remove", .boolean, "Remove the key at that frame", default: .bool(false),
                                 cli: .flag("remove")),
                baseRevision,
            ]),
        CommandSpec(
            "captions.words", .edit,
            "Show caption words as they are spoken (Inspector › Text › Word by word): highlight colours the word being "
                + "said, karaoke colours the words already said, reveal makes words appear as they are said; none shows "
                + "them all at once. Timings come from the transcription's word timings (captions generate) or are "
                + "estimated from word length.",
            parameters: [
                CommandParameter("item", .string, "Text item ID; the selection by default", cli: .positional),
                CommandParameter("style", .string, "Word style", required: true,
                                 choices: CaptionWords.styles + ["none"], cli: .option("style")),
                CommandParameter("all", .boolean, "Every caption on the caption layers", default: .bool(false),
                                 cli: .flag("all")),
                CommandParameter("color", .string, "Highlight colour, #RRGGBB (default #FFD400)", cli: .option("color")),
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
