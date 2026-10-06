import Foundation

/// "Save selection as…" (#80): the params of a new library item taken from what is selected on the timeline.
public enum LibrarySelection {
    /// The kinds a selection can be saved as.
    public static let kinds: [LibraryKind] = [.textPreset, .effectPreset, .transitionPreset, .look]

    /// Item properties an effect preset keeps: framing and its animation.
    static let effectProperties = ["transform", "keyframes"]

    /// The params for a `kind` item made from the timeline `item`, or from `transition` (the selected clip's) and
    /// the media of the sound a preset placed at its cut: one copied from an audio library item is kept as `sfx`.
    /// A look keeps the item's whole filter stack (#79): its grade and, given `lut` (the project LUT the grade
    /// uses), the LUT's strength and name; the caller saves the LUT's file as the item's file.
    public static func params(
        _ kind: LibraryKind, item: Item?, transition: TimelineTransition? = nil, sound: Media? = nil,
        lut: ColorLUT? = nil
    ) throws -> [String: JSONValue] {
        switch kind {
        case .textPreset:
            guard let item, let text = item["text"]?.string else {
                throw ProjectError.invalid("Select a text item to save its style")
            }
            return ["textPreset": .string(item["textPreset"]?.string ?? "bold-outline"), "text": .string(text)]
        case .effectPreset:
            return try effect(item)
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

    private static func effect(_ item: Item?) throws -> [String: JSONValue] {
        guard let item else { throw ProjectError.invalid("Select a clip to save its framing") }
        var patch: [String: JSONValue] = [:]
        for key in effectProperties { patch[key] = item[key] }
        guard !patch.isEmpty else { throw ProjectError.invalid("The selected item has no framing or keyframes to save") }
        return ["patch": .object(patch)]
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
