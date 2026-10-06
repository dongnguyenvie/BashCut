import Foundation

/// "Save selection as…" (#80): the params of a new library item taken from what is selected on the timeline.
public enum LibrarySelection {
    /// The kinds a selection can be saved as.
    public static let kinds: [LibraryKind] = [.textPreset, .effectPreset, .transitionPreset, .look]

    /// Item properties an effect preset keeps: framing and its animation.
    static let effectProperties = ["transform", "keyframes"]
    /// Grade fields that point into one project, so a look cannot carry them.
    static let projectColorFields = ["lut", "lutStrength"]

    /// The params for a `kind` item made from the timeline `item`, or from `transition` (the selected clip's).
    public static func params(
        _ kind: LibraryKind, item: Item?, transition: TimelineTransition? = nil
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
            return ["kind": .string(transition.kind), "duration": .integer(transition.duration)]
        case .look:
            return try look(item)
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

    private static func look(_ item: Item?) throws -> [String: JSONValue] {
        var color = item?["color"]?.object ?? [:]
        for key in projectColorFields { color[key] = nil }
        guard !color.isEmpty else { throw ProjectError.invalid("Select a graded clip or adjustment to save its look") }
        return ["color": .object(color)]
    }
}
