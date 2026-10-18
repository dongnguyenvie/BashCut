import BashCutProject

extension CommandCatalog {
    private static let motionPresets: String = MotionPreset.all.map(\.id).joined(separator: ", ")
    private static let eases: String = ItemMotion.Ease.summary
    private static let motionSummary: String =
        "Animate a clip, image or text over its length (Inspector › Animation): a preset (\(motionPresets); none "
        + "removes the animation) sized to the item, or keyframes JSON {property: [{frame, value, ease?}, …]} with "
        + "frames from the item's start. Properties: zoom, pan, tilt (px, up), rotation (degrees), opacity, and volume "
        + "(dB, like volumeDb; the only one on audio items, none on text); ease: \(eases) (default inOut). Keys "
        + "replace the item's static value for that property. Images with zoom-in, zoom-out or pan-* make a Ken Burns "
        + "move; presets are for pictures and text. focus frames a rectangle of a video clip (a panel of a screen "
        + "recording) without working out zoom, pan and tilt by hand, inside the band of the frame that stays visible: "
        + "by default the part no opaque picture on a higher layer covers edge to edge (the bottom half under a camera "
        + "across the top of a split layout), or within. The result gives within, the band used in canvas pixels."

    /// Caption import (generation is with the plugin capabilities).
    static let captionSpecs: [CommandSpec] = [
        CommandSpec(
            "captions.export", .read,
            "Export the captions (text on text layers, in time order) as: srt (default), SubRip text; json as "
                + "{revision, fps, cues} with per cue index, item, track, trackRole, at/end/duration (frames), atSeconds, "
                + "endSeconds, seconds, text, lines, chars (line breaks read as one space), cps, gapBefore (frames since "
                + "the previous cue ended, negative when they overlap), captionMedia, wordStyle, wordTiming "
                + "(transcribed or estimated from word length) and words [{text, at, end, atSeconds, endSeconds, "
                + "source}]; text, one line per cue: #index start–end seconds cps | text (print it with --format text).",
            parameters: [
                CommandParameter("as", .string, "srt (default), json or text", choices: ["srt", "json", "text"],
                                 cli: .option("as"))
            ]),
        CommandSpec(
            "transcript.words", .read,
            "Read every word on the caption layers in timeline order: index, text, at/end (frames), atSeconds, "
                + "endSeconds, item and cue (captions export numbering), timing (transcribed or estimated from word "
                + "length), gapBefore (frames since the previous word ended) and, for captions made from a media, "
                + "source {media, clip, start, end} in that media's seconds through the clip heard there now (null "
                + "when no clip of it plays there: captions do not move with their clips, except through a speed change). count is the words "
                + "returned, total the words on the caption layers. With heard, the words come from the stored "
                + "transcripts (media.transcribe) of the media the timeline plays instead: each word inside a clip "
                + "that plays it, at that clip's frames (trim, speed), with item = the clip, timing source and the "
                + "provider's confidence/speaker/event/noSpeechProb/avgLogprob/compressionRatio; transcribed and untranscribed list the media.",
            parameters: [
                CommandParameter("from", .integer, "Only words ending after this timeline frame", minimum: 0,
                                 cli: .option("from")),
                CommandParameter("to", .integer, "Only words starting before this timeline frame", minimum: 0,
                                 cli: .option("to")),
                CommandParameter("media", .string, "Only captions made from (or with heard, words of) this media ID",
                                 cli: .option("media")),
                CommandParameter("heard", .boolean, "Words of the source transcripts heard through the clips now",
                                 cli: .flag("heard")),
            ]),
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
                + "changes (2× halves it; rounded down to a whole frame, so the out edge never plays past the source it "
                + "played), moving later clips on its layer; with keepDuration it keeps its length and uses more or less "
                + "source. Linked picture and sound change together, and captions made from the clip's media follow the "
                + "clips the change retimed or moved, word timings included. A clip is shortened to fit its source even "
                + "with keepDuration; the result then has shortened: true. With items, every listed clip changes in one "
                + "undo step, each by these rules (Inspector with several clips selected); items that have no speed are "
                + "returned as skipped.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("items", .string, "Several item IDs, comma separated", cli: .option("items")),
                CommandParameter("speed", .number, "Speed, for example 0.5, 1.5 or 2", required: true,
                                 range: Project.speedRange, cli: .option("speed")),
                CommandParameter("keepDuration", .boolean, "Keep the clip's length instead", default: .bool(false),
                                 cli: .flag("keep-duration")),
                CommandParameter("preservePitch", .boolean, "Keep the voice pitch (on by default)",
                                 cli: .option("preserve-pitch")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.volume", .edit,
            "Set a clip's gain in dB (Inspector › Volume; op setProperties {volumeDb}). 0 leaves it as recorded, -6 "
                + "halves it, positive is louder. Linked picture and sound change together. With items, "
                + "every listed clip changes in one undo step; items without sound (text, images, graphics) are "
                + "returned as skipped. Volume keyframes (clip keyframe --property volume) still win where they are set.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("items", .string, "Several item IDs, comma separated", cli: .option("items")),
                CommandParameter("db", .number, "Gain in dB, for example -4 or 3", required: true,
                                 range: Project.volumeDbRange, cli: .option("db")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.speed-curve", .edit,
            "Give a clip a speed ramp (CapCut Curve) like Inspector › Speed › Curve: a preset ("
                + SpeedCurve.presets.map(\.id).joined(separator: ", ") + ", or none to remove it) or points "
                + "[[t, speed], …] with t from 0 (clip start) to 1 (clip end). The clip keeps its source and its length "
                + "follows the average speed unless keepDuration (still shortened to fit its source, reported as shortened: "
                + "true); linked sound and captions made from its media follow; one undo step.",
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
                CommandParameter("focus", .string, "Frame a rectangle of a video clip's picture: x,y,width,height in "
                                 + "source pixels from the top left (media.list width/height); sets zoom, pan and tilt "
                                 + "and keeps the other keys", cli: .option("focus")),
                CommandParameter("focusTo", .string, "With focus: move to this rectangle by the item's last frame",
                                 cli: .option("focus-to")),
                CommandParameter("within", .string, "With focus: where on the frame the rectangle lands: "
                                 + MotionFocus.Within.summary + "; auto (default) is the band higher layers leave "
                                 + "visible at the item's start (its end for focus-to), full the whole frame",
                                 cli: .option("within")),
                CommandParameter("ease", .string, "With focus-to: the move's ease (" + eases + ")", cli: .option("ease")),
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
                CommandParameter("ease", .string, "Change to the next key: " + eases, cli: .option("ease")),
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
        reframeSpec, moveItemsSpec,
        CommandSpec(
            "clip.backdrop", .edit,
            "Fill a fitted picture's bars with a blur of itself or a colour (Inspector › Video › Backdrop). blur "
                + "draws a blurred copy of the same frame scaled to fill, color a "
                + "solid colour; none removes it. The backdrop moves, fades and grades with the clip. blur is the "
                + "radius as a share of the frame's short side, dim darkens it (0–1). Several items in one undo step. "
                + "Returns rev and items.",
            parameters: [
                CommandParameter("item", .string, "Video or image item ID; the selection by default", cli: .positional),
                CommandParameter("items", .string, "Several item IDs, comma separated", cli: .option("items")),
                CommandParameter("kind", .string, "blur, color or none", required: true,
                                 choices: ["blur", "color", "none"], cli: .option("kind")),
                CommandParameter("color", .string, "Colour #RRGGBB for kind color (default black)", cli: .option("color")),
                CommandParameter("blur", .number, "Blur radius, share of the short side (default 0.05)", range: 0...0.5,
                                 cli: .option("blur")),
                CommandParameter("dim", .number, "Darkening, 0–1 (default 0)", range: 0...1, cli: .option("dim")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.transition", .edit,
            "Give a text, sticker, graphic or overlay item a transition kind as its own entrance or exit (Inspector › "
                + "In and Out), played inside the item's frame: enter plays the kind's incoming side over its first "
                + "frames, exit its outgoing side (a wipe or shape runs backwards) over its last; a whip or zoom fades "
                + "the item on the way. A cut transition at the same edge of a clip wins. Kinds as on upsertTransition; "
                + "none removes. Stored as the item's enter and exit fields. Returns rev and items.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selection by default", cli: .positional),
                CommandParameter("items", .string, "Several item IDs, comma separated", cli: .option("items")),
                CommandParameter("side", .string, "in, out or both", required: true, choices: ["in", "out", "both"],
                                 cli: .option("side")),
                CommandParameter("kind", .string, "Transition kind, or none", required: true,
                                 choices: TimelineTransition.renderedKinds + ["none"], cli: .option("kind")),
                CommandParameter("frames", .integer, "Length in frames; the item's own or half a second by default",
                                 minimum: 1, maximum: ItemTransition.maximumDuration, cli: .option("frames")),
                CommandParameter("easing", .string, "linear, in, out, inOut or cubic-bezier(x1,y1,x2,y2)",
                                 cli: .option("easing")),
                baseRevision,
            ]),
        CommandSpec(
            "text.line-style", .edit,
            "Give one text line its own font, size and colours (two fonts in one title; Inspector › Text › Lines). font "
                + "is a PostScript name from fonts list (family and weight), scale (× the block's font "
                + "size; the line is fitted to the frame on its own), fill and stroke (#RRGGBB). line counts from the top "
                + "(0), negative from the bottom. Stored in textStyle.lines (one entry per line, null keeps the block's "
                + "look); given fields merge into the line's, \"none\" removes one, clear drops the line's look. One undo "
                + "step. Returns rev, item and lines.",
            parameters: [
                CommandParameter("item", .string, "Text item ID; the selection by default", cli: .positional),
                CommandParameter("line", .integer, "Line from the top (0), negative from the bottom", required: true,
                                 cli: .option("line")),
                CommandParameter("font", .string, "Font PostScript name, or none", cli: .option("font")),
                CommandParameter("scale", .number, "Size × the block's font size", range: TextLineStyles.scaleRange,
                                 cli: .option("scale")),
                CommandParameter("fill", .string, "Text colour #RRGGBB, or none", cli: .option("fill")),
                CommandParameter("stroke", .string, "Outline colour #RRGGBB, or none", cli: .option("stroke")),
                CommandParameter("clear", .boolean, "Drop the line's own look", cli: .flag("clear")),
                baseRevision,
            ]),
        CommandSpec(
            "clip.reverse", .edit,
            "Play a video clip backwards (with its linked sound): renders a reversed copy of the source it uses into "
                + "the project's reversed/ folder and points the clip at it. Reversing again restores the original.",
            parameters: [CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional)],
            execution: .job),
        CommandSpec(
            "clip.freeze", .edit,
            "Hold one frame of a video clip for its whole length, like the clip menu's Freeze Frame (ui action "
                + "clip.freeze): the frame the clip shows at atFrame (the playhead by default), as one undo step; "
                + "freezing a frozen clip picks again from its source; off removes the freeze. A frozen clip has no "
                + "speed and cannot be reversed. Returns freezeFrame, the source frame held.",
            parameters: [
                CommandParameter("item", .string, "Item ID; the selected clip by default", cli: .positional),
                CommandParameter("atFrame", .integer, "Timeline frame inside the clip; the playhead by default",
                                 minimum: 0, cli: .option("at-frame")),
                CommandParameter("off", .boolean, "Remove the freeze frame", default: .bool(false), cli: .flag("off")),
                baseRevision,
            ]),
    ]

    /// Subject-aware crop (P3-J1).
    static let reframeSpec = CommandSpec(
        "clip.reframe", .edit,
        "Crop a clip or image to its subject from media.subjects face boxes: the clip "
            + "fills the frame and pans (and tilts) so the subject's centre sits at anchor. mode locked holds one "
            + "framing (the subject's median place), cut jumps to a new framing (hold keys) when the subject moves more "
            + "than drift of the frame and the last framing held minHold seconds, follow keys pan and tilt at every "
            + "sampled picture, averaged over smooth seconds. Boxes stored for the source the clip plays are used; "
            + "missing ones are measured first with a vision.faces provider (every step source seconds) and stored. "
            + "When fewer than minSubjectShare of the clip's pictures have a subject, or the framing keeps less than "
            + "gate of the subject in view on average, it fits the whole picture instead (fallback fit) or changes "
            + "nothing (fallback refuse); never a blind centre crop. The defaults are starting points, not verdicts: "
            + "set them from the skill's ranges. One undo step (fill, transform, zoom/pan/tilt keys; other keys stay). "
            + "Returns rev, applied (reframe or fit), reason, coverage {samples, subjectSamples, subjectShare, mean, "
            + "min} (share of the subject box in view), segments [{frame (from the item's start), pan, tilt}], "
            + "measured (whether boxes were measured now) and preview {path, rows} (source next to the edit at each "
            + "framing and the least covered picture). A job.",
        parameters: [
            CommandParameter("item", .string, "Video or image item ID; the selection by default", cli: .positional),
            CommandParameter("mode", .string, "locked (default), cut or follow",
                             choices: SubjectReframe.Mode.allCases.map(\.rawValue), cli: .option("mode")),
            CommandParameter("subject", .string, "face (the largest face, default), faces (all faces) or person",
                             choices: SubjectReframe.Subject.allCases.map(\.rawValue), cli: .option("subject")),
            CommandParameter("minConfidence", .number, "Ignore boxes below this confidence (default 0.5)", range: 0...1,
                             cli: .option("min-confidence")),
            CommandParameter("anchor", .string, "Where the subject's centre sits: x,y as shares of the frame from the "
                             + "top left (default 0.5,0.5)", cli: .option("anchor")),
            CommandParameter("zoom", .number, "Scale over the filled size (default 1)", range: 1...10, cli: .option("zoom")),
            CommandParameter("gate", .number, "Least mean share of the subject in view (default 0.9)", range: 0...1,
                             cli: .option("gate")),
            CommandParameter("minSubjectShare", .number, "Least share of pictures with a subject (default 0.5)",
                             range: 0...1, cli: .option("min-subject-share")),
            CommandParameter("fallback", .string, "Below the gate: fit (default) or refuse",
                             choices: SubjectReframe.Fallback.allCases.map(\.rawValue), cli: .option("fallback")),
            CommandParameter("drift", .number, "cut: share of the frame the subject may move before a new framing "
                             + "(default 0.15)", range: 0...1, cli: .option("drift")),
            CommandParameter("minHold", .number, "cut: shortest framing in seconds (default 1)", range: 0...600,
                             cli: .option("min-hold")),
            CommandParameter("smooth", .number, "follow: seconds the path is averaged over (default 1)", range: 0...60,
                             cli: .option("smooth")),
            CommandParameter("step", .number, "Source seconds between pictures when measuring (default 0.5)",
                             range: 0.04...60, cli: .option("step")),
            CommandParameter("measure", .boolean, "Measure the boxes again even when stored", cli: .flag("measure")),
            provider,
            baseRevision,
        ],
        execution: .job)

    /// Moving a selection (#357 follow-up).
    static let moveItemsSpec = CommandSpec(
        "timeline.move-items", .edit,
        "Move several items together in one undo step, like dragging a timeline selection: by shifts each item "
            + "that many frames on its own layer, keeping their offsets (items on a magnetic layer stay; one landing "
            + "on another clip spills to a free layer); before moves the given items of the magnetic layer track (Main "
            + "by default) as one block, in their order, before that clip (an item outside the list) or to the end "
            + "(end); the layer packs again and linked sound follows. Give by or before. Returns rev and items.",
        parameters: [
            CommandParameter("items", .string, "Item IDs, comma separated", required: true, cli: .option("items")),
            CommandParameter("by", .integer, "Frames to move (negative: earlier)", cli: .option("by")),
            CommandParameter("before", .string, "Magnetic layer: the clip the block goes before, or end",
                             cli: .option("before")),
            CommandParameter("track", .string, "The magnetic layer for before (default: the main layer)",
                             cli: .option("track")),
            baseRevision,
        ])
}
