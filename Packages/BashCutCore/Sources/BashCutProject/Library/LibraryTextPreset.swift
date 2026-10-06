import Foundation

/// A text preset item's params (#380): `textPreset` (a renderer preset, `TextPreset.all`) and `text` (the sample the
/// panel shows and the text placed by default), with an optional `textStyle` (the item's own size, position and
/// outline over the preset's: the `textStyle` fields of `ItemProperty.all`, with the same ranges) and `animation` (a
/// `MotionPreset` id). Items without `textStyle` or `animation` behave as before. Other keys round-trip.
public struct LibraryTextPreset: Sendable, Equatable {
    /// The `textStyle` fields an item may store: every declared item `textStyle` property.
    public static let styleKeys: [String] = ItemProperty.all.filter { $0.group == "textStyle" }.map(\.key)

    public var textPreset: String
    public var text: String?
    /// Only `styleKeys`; empty when the item keeps the preset's look.
    public var textStyle: [String: JSONValue]
    public var animation: String?

    public init(
        textPreset: String, text: String? = nil, textStyle: [String: JSONValue] = [:], animation: String? = nil
    ) {
        self.textPreset = textPreset
        self.text = text
        self.textStyle = textStyle
        self.animation = animation
    }

    /// Reads and checks `params`.
    public init(params: [String: JSONValue], label: String = "text preset") throws {
        guard let preset = params["textPreset"]?.string, TextPreset.all.contains(preset) else {
            throw ProjectError.invalid(
                "\(label): params.textPreset must be one of \(TextPreset.all.joined(separator: ", "))")
        }
        textPreset = preset
        if let value = params["text"] {
            guard let text = value.string else { throw ProjectError.invalid("\(label): params.text must be text") }
            self.text = text
        }
        textStyle = try params["textStyle"].map { try Self.style($0, label: label) } ?? [:]
        if let value = params["animation"] {
            guard let id = value.string, id == "none" || MotionPreset.all.contains(where: { $0.id == id }) else {
                let ids = MotionPreset.all.map(\.id).joined(separator: ", ")
                throw ProjectError.invalid("\(label): params.animation must be none or one of \(ids)")
            }
            animation = id == "none" ? nil : id
        }
    }

    /// Checks a stored `textStyle`: an object of `styleKeys` whose values fit the item property's rule.
    private static func style(_ value: JSONValue, label: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = value else {
            throw ProjectError.invalid("\(label): params.textStyle must be an object")
        }
        for (key, value) in fields {
            guard let property = ItemProperty.all.first(where: { $0.group == "textStyle" && $0.key == key }) else {
                throw ProjectError.invalid(
                    "\(label): params.textStyle.\(key) is not stored; use \(styleKeys.joined(separator: ", "))")
            }
            if let expected = property.rule.mismatch(value) {
                throw ProjectError.invalid("\(label): params.textStyle.\(key): expected \(expected)")
            }
        }
        return fields
    }

    /// The style of the timeline text `item` on `project`: its preset, text, the stored `textStyle` fields and, when
    /// its keyframes are exactly a motion preset at its length, that preset. Hand-made keys are not kept.
    public init(item: Item, project: Project?) {
        self.init(textPreset: item.textPreset ?? "bold-outline", text: item["text"]?.string)
        let style = item["textStyle"]?.object ?? [:]
        for key in Self.styleKeys {
            guard let value = style[key], let number = value.double else { continue }
            textStyle[key] = LibrarySticker.rounded(number)
        }
        if let motion = item.motion, let project {
            animation = MotionPreset.all.first { preset in
                (try? MotionPreset.motion(
                    preset.id, duration: item.duration, width: project.width, height: project.height, fps: project.fps
                )) == motion
            }?.id
        }
    }

    /// The params as a library item stores them, merged over `params` so unknown keys stay.
    public func params(merging params: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var params = params
        for key in ["textPreset", "text", "textStyle", "animation"] { params[key] = nil }
        params["textPreset"] = .string(textPreset)
        if let text { params["text"] = .string(text) }
        if !textStyle.isEmpty { params["textStyle"] = .object(textStyle) }
        if let animation { params["animation"] = .string(animation) }
        return params
    }

    /// The properties that give the text `item` (on `project`) this style: the preset, the stored style over the
    /// item's own `textStyle` (other fields such as a caption highlight stay) and, with an animation, its keys at
    /// the item's length. Without a stored style or animation, only the preset, as before #380.
    public func patch(for item: Item, project: Project) throws -> [String: JSONValue] {
        var patch: [String: JSONValue] = ["textPreset": .string(textPreset)]
        if !textStyle.isEmpty {
            patch["textStyle"] = .object((item["textStyle"]?.object ?? [:]).merging(textStyle) { $1 })
        }
        if let animation {
            patch["keyframes"] = try MotionPreset.motion(
                animation, duration: item.duration, width: project.width, height: project.height, fps: project.fps
            ).json
        }
        return patch
    }
}
