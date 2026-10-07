import Foundation

/// A text preset item's params (#380, opened by C10): `textPreset` (any 1–80 character name; the renderer's own
/// presets give their defaults, others draw with bold-outline's), `text` (the sample the panel shows and the text
/// placed by default), an optional `textStyle` (the item's own style over the preset's: any `textStyle` field — the
/// declared ones of `ItemProperty.all` are checked with the same rules, others such as `background` and `shadow` are
/// kept as given), `wordStyle` (as on items) and `animation` (a `MotionPreset` id, or a `MotionTemplate` object of
/// keys at t 0–1 or seconds). Items without `textStyle` or `animation` behave as before. Other keys round-trip.
public struct LibraryTextPreset: Sendable, Equatable {
    /// The declared `textStyle` fields: every item `textStyle` property.
    public static let styleKeys: [String] = ItemProperty.all.filter { $0.group == "textStyle" }.map(\.key)

    public var textPreset: String
    public var text: String?
    /// Empty when the item keeps the preset's look.
    public var textStyle: [String: JSONValue]
    /// A word style name or `{spoken, upcoming, past}` states; nil keeps the item's.
    public var wordStyle: JSONValue?
    /// A motion preset id.
    public var animation: String?
    /// Hand-made keys, when the animation is not a preset.
    public var animationKeys: MotionTemplate?

    public init(
        textPreset: String, text: String? = nil, textStyle: [String: JSONValue] = [:], animation: String? = nil,
        wordStyle: JSONValue? = nil, animationKeys: MotionTemplate? = nil
    ) {
        self.textPreset = textPreset
        self.text = text
        self.textStyle = textStyle
        self.animation = animation
        self.wordStyle = wordStyle
        self.animationKeys = animationKeys
    }

    /// Reads and checks `params`.
    public init(params: [String: JSONValue], label: String = "text preset") throws {
        guard let preset = params["textPreset"]?.string, (1...80).contains(preset.count) else {
            throw ProjectError.invalid("\(label): params.textPreset must be a name of 1–80 characters")
        }
        textPreset = preset
        if let value = params["text"] {
            guard let text = value.string else { throw ProjectError.invalid("\(label): params.text must be text") }
            self.text = text
        }
        textStyle = try params["textStyle"].map { try Self.style($0, label: label) } ?? [:]
        if let value = params["wordStyle"], value != .null {
            var probe = Item(id: "preset", at: 0, duration: 1)
            probe["wordStyle"] = value
            do { try probe.validateWords() } catch {
                throw ProjectError.invalid("\(label): params.wordStyle: expected a word style name or state objects")
            }
            wordStyle = value
        }
        switch params["animation"] {
        case nil, .null?: break
        case .string(let id)?:
            guard id == "none" || MotionPreset.all.contains(where: { $0.id == id }) else {
                let ids = MotionPreset.all.map(\.id).joined(separator: ", ")
                throw ProjectError.invalid("\(label): params.animation must be none, one of \(ids) or keys")
            }
            animation = id == "none" ? nil : id
        case let keys?:
            animationKeys = try MotionTemplate(json: keys, label: "\(label): params.animation")
        }
    }

    /// Checks a stored `textStyle`: an object whose declared fields fit the item property's rule.
    private static func style(_ value: JSONValue, label: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = value else {
            throw ProjectError.invalid("\(label): params.textStyle must be an object")
        }
        for (key, value) in fields {
            guard let property = ItemProperty.all.first(where: { $0.group == "textStyle" && $0.key == key }) else {
                continue
            }
            if let expected = property.rule.mismatch(value) {
                throw ProjectError.invalid("\(label): params.textStyle.\(key): expected \(expected)")
            }
        }
        return fields
    }

    /// The style of the timeline text `item` on `project`: its preset, text, its whole `textStyle` (declared numbers
    /// rounded), its word style and its keyframes — the motion preset they are at its length, else the keys as a
    /// template (t 0–1 of its length, values as stored).
    public init(item: Item, project: Project?) {
        self.init(textPreset: item.textPreset ?? "bold-outline", text: item["text"]?.string)
        for (key, value) in item["textStyle"]?.object ?? [:] {
            if let number = value.double, Self.styleKeys.contains(key) {
                textStyle[key] = LibrarySticker.rounded(number)
            } else {
                textStyle[key] = value
            }
        }
        if let value = item["wordStyle"], value != .null { wordStyle = value }
        guard let motion = item.motion else { return }
        if let project {
            animation = MotionPreset.all.first { preset in
                (try? MotionPreset.motion(
                    preset.id, duration: item.duration, width: project.width, height: project.height, fps: project.fps
                )) == motion
            }?.id
        }
        if animation == nil { animationKeys = Self.template(motion, duration: item.duration) }
    }

    /// Keys at t 0–1 of an item of `duration` frames.
    private static func template(_ motion: ItemMotion, duration: Int) -> MotionTemplate? {
        let end = Double(max(1, duration - 1))
        let json = JSONValue.object(motion.keys.mapValues { keys in
            .array(keys.map { key in
                var fields: [String: JSONValue] = [
                    "t": .number((min(max(0, Double(key.frame) / end), 1) * 10_000).rounded() / 10_000),
                    "value": .number(key.value),
                ]
                if key.ease != .easeInOut { fields["ease"] = .string(key.ease.rawValue) }
                return .object(fields)
            })
        })
        return try? MotionTemplate(json: json)
    }

    /// The params as a library item stores them, merged over `params` so unknown keys stay.
    public func params(merging params: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var params = params
        for key in ["textPreset", "text", "textStyle", "wordStyle", "animation"] { params[key] = nil }
        params["textPreset"] = .string(textPreset)
        if let text { params["text"] = .string(text) }
        if !textStyle.isEmpty { params["textStyle"] = .object(textStyle) }
        if let wordStyle { params["wordStyle"] = wordStyle }
        if let animation { params["animation"] = .string(animation) } else if let animationKeys {
            params["animation"] = animationKeys.json
        }
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
        if let wordStyle { patch["wordStyle"] = wordStyle }
        if let animation {
            patch["keyframes"] = try MotionPreset.motion(
                animation, duration: item.duration, width: project.width, height: project.height, fps: project.fps
            ).json
        } else if let animationKeys {
            patch["keyframes"] = try animationKeys.motion(
                duration: item.duration, width: project.width, height: project.height, fps: project.fps
            ).json
        }
        return patch
    }
}
