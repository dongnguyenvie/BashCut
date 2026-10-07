import Foundation

/// "Save selection as…" (#80): the params of a new library item taken from what is selected on the timeline.
public enum LibrarySelection {
    /// The kinds a selection can be saved as.
    public static let kinds: [LibraryKind] = [.textPreset, .effectPreset, .transitionPreset, .look, .audio, .sticker]

    /// The params for a `kind` item made from the timeline `item`, or from `transition` (the selected clip's) and
    /// the media of the sound a preset placed at its cut: one copied from an audio library item is kept as `sfx`.
    /// A look keeps the item's whole filter stack (#79): its grade and, given `lut` (the project LUT the grade
    /// uses), the LUT's strength and name; the caller saves the LUT's file as the item's file.
    /// An effect preset (#76) becomes a recipe of what is on the clip: reverse, speed or speed ramp, framing,
    /// keyframes (as positions 0–1 so they scale with the next clip) and the sound effect at its start, given as
    /// `soundItem` (the SFX item) and `sound` (its media; one copied from an audio library item is kept as `sfx`).
    /// A text preset keeps the item's preset, text, `textStyle` and its motion preset (#380), told on `project`'s frame.
    public static func params(
        _ kind: LibraryKind, item: Item?, transition: TimelineTransition? = nil, sound: Media? = nil,
        lut: ColorLUT? = nil, soundItem: Item? = nil, project: Project? = nil
    ) throws -> [String: JSONValue] {
        switch kind {
        case .textPreset:
            guard let item, item["text"]?.string != nil else {
                throw ProjectError.invalid("Select a text item to save its style")
            }
            return LibraryTextPreset(item: item, project: project).params()
        case .effectPreset:
            return try effect(item, soundItem: soundItem, sound: sound)
        case .transitionPreset:
            guard let transition else {
                throw ProjectError.invalid("Select a clip that has a transition to save it")
            }
            let sfx = sound?[TransitionPreset.soundLibraryField]?.string
            return TransitionPreset(
                kind: transition.kind, duration: transition.duration, easing: transition.easing, sfx: sfx
            ).params
        case .look:
            return try look(item, lut: lut)
        case .audio:
            guard let sound else { throw ProjectError.invalid("Select an audio clip, or pass a project audio media item") }
            return try audio(sound, trackRole: nil)
        case .sticker:
            return try sticker(item, media: nil, project: nil)
        case .voice, .clip:
            throw ProjectError.invalid("A selection cannot be saved as \(kind.rawValue)")
        }
    }

    /// A sticker (#64) from an overlay item: an emoji text item as an emoji sticker with its text preset, or an image
    /// or movie item (`media`, on `project`'s frame) as an image, animated or video-alpha sticker with its size,
    /// position and length. `frames` is the image file's frame count; a movie is a sticker only with `alpha` media.
    /// The caller saves the media's file as the item's file.
    public static func sticker(
        _ item: Item?, media: Media?, project: Project?, frames: Int = 1
    ) throws -> [String: JSONValue] {
        if let text = item?["text"]?.string {
            let emoji = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !emoji.isEmpty, emoji.count <= 32 else {
                throw ProjectError.invalid("The text is too long for an emoji sticker; save it as a text style instead")
            }
            return LibrarySticker(stickerKind: "emoji", emoji: emoji)
                .params(merging: ["textPreset": .string(item?["textPreset"]?.string ?? "bold-outline")])
        }
        guard let item, let media, let project else {
            throw ProjectError.invalid("Select an image or emoji overlay item to save it as a sticker")
        }
        let kind: String
        switch media.kind {
        case "image": kind = frames > 1 ? "animated" : "image"
        case "video" where media["alpha"]?.bool == true: kind = "video-alpha"
        default:
            throw ProjectError.invalid(
                "\(item.id) is not an image or a movie with alpha; only those can be saved as stickers")
        }
        let transform = item["transform"]?.object ?? [:]
        let pictureWidth = media.width ?? project.width, pictureHeight = media.height ?? project.height
        // A filling item covers the frame; its framing is not a sticker's, so it keeps only the length.
        var sticker = LibrarySticker(stickerKind: kind, seconds: Double(item.duration) / project.fps.value)
        if !project.fills(item) {
            let placed = StickerFraming(
                pictureWidth: pictureWidth, pictureHeight: pictureHeight, width: project.width, height: project.height
            ).placement(
                zoom: transform["zoom"]?.double ?? 1, pan: transform["pan"]?.double ?? 0,
                tilt: transform["tilt"]?.double ?? 0)
            sticker.size = min(LibrarySticker.sizeRange.upperBound, max(LibrarySticker.sizeRange.lowerBound, placed.size))
            sticker.position = .point(x: min(1, max(0, placed.x)), y: min(1, max(0, placed.y)))
        }
        var params = sticker.params()
        params["width"] = .integer(pictureWidth)
        params["height"] = .integer(pictureHeight)
        if frames > 1 { params["frames"] = .integer(frames) }
        return params
    }

    /// An audio item (#78) from project audio media: its length, and a role from the layer its clip is on (`trackRole`;
    /// a Music layer gives music, an SFX layer sfx). The caller saves the media's file as the item's file.
    public static func audio(_ media: Media, trackRole: String?) throws -> [String: JSONValue] {
        guard media.kind == "audio", media.frames > 0 else {
            throw ProjectError.invalid("\(media.id) is not audio media; save an audio file or clip")
        }
        let role: String? = switch trackRole {
        case TrackRole.sfx: "sfx"
        case TrackRole.music: "music"
        default: nil
        }
        return LibraryAudio(role: role, seconds: media.durationSeconds).params()
    }

    private static func effect(_ item: Item?, soundItem: Item?, sound media: Media?) throws -> [String: JSONValue] {
        guard let item else { throw ProjectError.invalid("Select a clip to save its effect") }
        var steps: [[String: JSONValue]] = []
        if item["reversed"] != nil { steps.append(["op": .string("reverse")]) }
        if let curve = item.speedCurve {
            steps.append(["op": .string("speedCurve"), "points": curve.json])
        } else if abs(item.speed - 1) > 1e-9 {
            steps.append(["op": .string("speed"), "speed": .number(item.speed)])
        }
        if let transform = item["transform"] { steps.append(["op": .string("patch"), "patch": .object(["transform": transform])]) }
        if let motion = item.motion { steps.append(keyframeStep(motion, duration: item.duration)) }
        if let soundItem, let media { steps.append(soundStep(soundItem, media: media, clip: item)) }
        guard !steps.isEmpty else {
            throw ProjectError.invalid("The selected item has no framing, keyframes, speed, reverse or sound effect to save")
        }
        return EffectRecipe(steps: steps).params
    }

    /// The item's keys at positions 0–1, so they scale with the clip a recipe is applied to.
    private static func keyframeStep(_ motion: ItemMotion, duration: Int) -> [String: JSONValue] {
        let last = Double(max(1, duration - 1))
        return ["op": .string("keyframes"), "keys": .object(motion.keys.mapValues { list in
            .array(list.map { key in
                var fields: [String: JSONValue] = [
                    "t": EffectRecipe.number((Double(key.frame) / last * 1_000_000).rounded() / 1_000_000),
                    "value": .number(key.value),
                ]
                if key.ease != .easeInOut { fields["ease"] = .string(key.ease.rawValue) }
                return .object(fields)
            })
        })]
    }

    /// The sound effect `sound` (its media `media`) at its offset from the clip's start.
    private static func soundStep(_ sound: Item, media: Media, clip: Item) -> [String: JSONValue] {
        var step: [String: JSONValue] = ["op": .string("sfx"), "frame": .integer(max(0, sound.at - clip.at))]
        if let library = media[TransitionPreset.soundLibraryField]?.string { step["sfx"] = .string(library) }
        if let volume = sound["volumeDb"]?.double, volume != 0, (-60...12).contains(volume) { step["volumeDb"] = .number(volume) }
        return step
    }

    /// The grade without its project LUT ID, which means nothing in another project. The LUT's strength stays
    /// only when the LUT itself is saved with the look.
    private static func look(_ item: Item?, lut: ColorLUT?) throws -> [String: JSONValue] {
        var color = item?["color"]?.object ?? [:]
        let keepsLUT = lut.map { color["lut"]?.string == $0.id } ?? false
        color["lut"] = nil
        if !keepsLUT { color["lutStrength"] = nil }
        guard !color.isEmpty || keepsLUT else {
            throw ProjectError.invalid("Select a graded clip or adjustment to save its look")
        }
        return FilterStack(color: color, lutName: keepsLUT ? lut?.name : nil).params
    }
}
