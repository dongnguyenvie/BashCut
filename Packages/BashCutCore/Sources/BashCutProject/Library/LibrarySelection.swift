import Foundation

/// "Save selection as…" (#80): the params of a new library item taken from what is selected on the timeline.
public enum LibrarySelection {
    /// The kinds a selection can be saved as.
    public static let kinds: [LibraryKind] = [.textPreset, .effectPreset, .transitionPreset, .look]

    /// The params for a `kind` item made from the timeline `item`, or from `transition` (the selected clip's) and
    /// the media of the sound a preset placed at its cut: one copied from an audio library item is kept as `sfx`.
    /// A look keeps the item's whole filter stack (#79): its grade and, given `lut` (the project LUT the grade
    /// uses), the LUT's strength and name; the caller saves the LUT's file as the item's file.
    /// An effect preset (#76) becomes a recipe of what is on the clip: reverse, speed or speed ramp, framing,
    /// keyframes (as positions 0–1 so they scale with the next clip) and the sound effect at its start, given as
    /// `soundItem` (the SFX item) and `sound` (its media; one copied from an audio library item is kept as `sfx`).
    public static func params(
        _ kind: LibraryKind, item: Item?, transition: TimelineTransition? = nil, sound: Media? = nil,
        lut: ColorLUT? = nil, soundItem: Item? = nil
    ) throws -> [String: JSONValue] {
        switch kind {
        case .textPreset:
            guard let item, let text = item["text"]?.string else {
                throw ProjectError.invalid("Select a text item to save its style")
            }
            return ["textPreset": .string(item["textPreset"]?.string ?? "bold-outline"), "text": .string(text)]
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
        case .audio, .sticker, .voice:
            throw ProjectError.invalid("A selection cannot be saved as \(kind.rawValue)")
        }
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
