import Foundation

// One declaration of the project format's typed fields. `Project.validate()` checks item properties from
// `ItemProperty.all`, and `ProjectSchema.document` turns the same tables into a JSON Schema (published as
// docs/reference/project.schema.json and by `schema get`). Adding a property is one entry here; rules that
// span several fields (overlaps, links, layer bands) stay in Swift validation and are described in the schema.

/// A typed, optional item property, at the top level of an item or inside one of its groups.
public struct ItemProperty: Sendable {
    public enum Rule: Sendable {
        case number(ClosedRange<Double>)
        case integer(ClosedRange<Int>)
        case boolean
        /// Text of 1…`maxLength` characters.
        case text(maxLength: Int)
        /// A `#RRGGBB` colour.
        case color
    }

    /// `nil` for a top-level item field, else the object it lives in (`transform`, `color`, `textStyle`).
    public let group: String?
    public let key: String
    public let rule: Rule
    public let summary: String

    init(_ group: String?, _ key: String, _ rule: Rule, _ summary: String) {
        self.group = group
        self.key = key
        self.rule = rule
        self.summary = summary
    }

    public static let groups = ["transform", "crop", "color", "textStyle"]

    public static let all: [ItemProperty] = [
        .init(nil, "speed", .number(0.01...100), "Source frames per timeline frame; the timeline duration is kept"),
        .init(nil, "opacity", .number(0...1), "Picture opacity"),
        .init(nil, "volumeDb", .number(-120...24), "Clip gain in dB"),
        .init(nil, "muted", .boolean, "Silences the clip"),
        .init(nil, "preservePitch", .boolean, "Keeps pitch when speed changes (default true)"),
        .init(nil, "fadeIn", .integer(0...2_000_000_000), "Audio fade-in in timeline frames"),
        .init(nil, "fadeOut", .integer(0...2_000_000_000), "Audio fade-out in timeline frames"),
        .init(nil, "fill", .boolean, "Fill the frame (cropping) instead of fitting inside it; the project's clipFill by default"),
        .init("transform", "zoom", .number(0.01...100), "Scale over the fitted or filled size"),
        .init("transform", "pan", .number(-65536...65536), "Horizontal offset in output pixels"),
        .init("transform", "tilt", .number(-65536...65536), "Vertical offset in output pixels"),
        .init("transform", "rotation", .number(-3600...3600), "Rotation in degrees, counterclockwise, around the frame centre"),
        .init("crop", "left", .number(0...0.95),
              "Video picture: fraction of the width hidden on the left (left + right at most 0.95)"),
        .init("crop", "right", .number(0...0.95), "Video picture: fraction of the width hidden on the right"),
        .init("crop", "top", .number(0...0.95),
              "Video picture: fraction of the height hidden at the top (top + bottom at most 0.95)"),
        .init("crop", "bottom", .number(0...0.95), "Video picture: fraction of the height hidden at the bottom"),
        .init("crop", "radius", .number(0...0.5),
              "Video picture: corner radius as a fraction of the visible part's shorter side (0.5 = circle or pill)"),
        .init("textStyle", "size", .number(0.005...1), "Font size as a fraction of the frame's short side (shrunk to fit 90% of the width)"),
        .init("textStyle", "positionY", .number(0...1), "Baseline position from the bottom, as a fraction"),
        .init("textStyle", "strokeWidth", .number(0...50), "Outline width in points"),
        .init("textStyle", "font", .text(maxLength: 128), "Font PostScript name (fonts list); missing fonts draw as Helvetica"),
        .init("textStyle", "fill", .color, "Text colour, #RRGGBB (the preset's by default)"),
        .init("textStyle", "stroke", .color, "Outline colour, #RRGGBB (default black)"),
        .init("textStyle", "highlight", .color, "Word-by-word highlight colour, #RRGGBB (default #FFD400)"),
    ] + ColorGrade.ranges.map { .init("color", $0.key, .number($0.range), ColorGrade.summaries[$0.key] ?? "") }
}

extension ColorGrade {
    public static let summaries = [
        "exposure": "Exposure in stops (0 = unchanged)",
        "contrast": "Contrast multiplier (1 = unchanged)",
        "saturation": "Saturation multiplier (0 = black and white, 1 = unchanged)",
        "lutStrength": "LUT mix (0 = off, 1 = full)",
    ]
}

extension Item {
    /// Checks every `ItemProperty`: groups are objects, values have the declared type and range.
    func validateDeclaredProperties() throws {
        for group in ItemProperty.groups {
            guard let value = fields[group] else { continue }
            guard case .object = value else { throw ProjectError.invalid("item.\(id).\(group): expected an object") }
        }
        // Walks the item's own fields (a handful) rather than every declared property; the first
        // mismatch in `ItemProperty.all` order is reported, as before.
        var first: (index: Int, expected: String)?
        func check(_ values: [String: JSONValue], group: String?) {
            for (key, value) in values {
                guard let index = ItemProperty.index[ItemProperty.Key(group: group, key: key)],
                    first.map({ index < $0.index }) ?? true,
                    let expected = ItemProperty.all[index].rule.mismatch(value)
                else { continue }
                first = (index, expected)
            }
        }
        check(fields, group: nil)
        for group in ItemProperty.groups {
            if case .object(let values) = fields[group] { check(values, group: group) }
        }
        guard let first else { return }
        let property = ItemProperty.all[first.index]
        let path = "item.\(id)." + (property.group.map { $0 + "." } ?? "") + property.key
        throw ProjectError.invalid("\(path): expected \(first.expected)")
    }
}

extension ItemProperty {
    struct Key: Hashable {
        let group: String?
        let key: String
    }

    /// Position of each property in `all`.
    static let index = Dictionary(
        all.enumerated().map { (Key(group: $1.group, key: $1.key), $0) }, uniquingKeysWith: { first, _ in first })
}

extension ItemProperty.Rule {
    /// What the value should have been, or nil when it fits.
    func mismatch(_ value: JSONValue) -> String? {
        switch self {
        case .number(let range):
            value.double.map { $0.isFinite && range.contains($0) } == true ? nil : "a number in \(range)"
        case .integer(let range):
            value.int.map(range.contains) == true ? nil : "an integer in \(range)"
        case .boolean:
            if case .bool = value { nil } else { "a boolean" }
        case .text(let maxLength):
            value.string.map { !$0.isEmpty && $0.count <= maxLength } == true ? nil : "text of 1…\(maxLength) characters"
        case .color:
            value.string.map(Self.isColor) == true ? nil : "a colour #RRGGBB"
        }
    }

    public static let colorPattern = "^#[0-9A-Fa-f]{6}$"

    static func isColor(_ text: String) -> Bool {
        text.count == 7 && text.first == "#" && text.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// The project format as JSON Schema (draft 2020-12). Unknown fields are allowed everywhere, because they
/// round-trip; only the declared fields are typed.
public enum ProjectSchema {
    public static var document: JSONValue {
        var root = fields(
            "A BashCut project (project.bashcut.json).",
            required: ["schema", "id", "name", "rev", "format", "tracks"],
            properties: [
                "schema": .object(["const": .string(Project.schema)]),
                "id": string("Stable project ID", minLength: 1),
                "name": string("Display name", minLength: 1),
                "rev": integer("Revision, +1 on every applied edit", minimum: 0),
                "clipFill": boolean(
                    "Clips fill the frame, cropping what does not fit, instead of fitting inside it. New projects "
                        + "fit (false); a project without it fills, as projects did before it existed"),
                "canvasFromFirstClip": boolean(
                    "The first video or image clip placed on the timeline sets the canvas shape (portrait, landscape or "
                        + "square, keeping the short side). Cleared by any canvas change, so a canvas set on purpose "
                        + "stays; absent in projects made before it existed"),
                "contentLanguage": string("BCP 47 language of speech and captions", pattern: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"),
                "format": object(
                    "Output format", required: ["width", "height", "fps"],
                    properties: [
                        "width": integer("Pixels", minimum: 1, maximum: 16384),
                        "height": integer("Pixels", minimum: 1, maximum: 16384),
                        "fps": ref("rational"), "sampleRate": integer("Hz", minimum: 1),
                    ]),
                "media": array("Source files", of: ref("media")),
                "tracks": array("Layers: visual kinds back to front, then audio", of: ref("track"), minItems: 1, maxItems: 256),
                "markers": array("Timeline markers", of: ref("marker"), maxItems: 10_000),
                "transitions": array("Transitions on adjacent video cuts", of: ref("transition"), maxItems: 10_000),
                "luts": array("Project .cube LUT catalog", of: ref("lut"), maxItems: 1_000),
                "looks": array("Custom looks (built-in looks are not stored)", of: ref("look"), maxItems: 1_000),
                "styleKits": array("Custom style kits (built-in kits are not stored)", of: ref("styleKit"), maxItems: 1_000),
                "audio": ref("audio"),
                "output": outputSchema,
                "review": reviewSchema,
                "beatGrid": object(
                    "Beat grid of one audio media", required: ["media", "bpm", "frames"],
                    properties: [
                        "media": string("Media ID"), "bpm": number("Beats per minute", 20...400),
                        "frames": array("Sorted unique timeline frames", of: integer("Frame", minimum: 0), maxItems: 100_000),
                    ]),
                "providers": .object([
                    "type": .string("object"), "description": .string("Preferred provider ID per capability"),
                    "additionalProperties": .object(["type": .string("string")]),
                ]),
            ])
        root["$schema"] = .string("https://json-schema.org/draft/2020-12/schema")
        root["$id"] = .string("https://bashcut.app/schema/\(Project.schema).json")
        root["title"] = .string("BashCut project")
        root["$defs"] = .object(definitions)
        return .object(root)
    }

    /// The published file's bytes: indented, sorted keys, trailing newline.
    public static func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document) + Data("\n".utf8)
    }

    private static var definitions: [String: JSONValue] {
        [
            "rational": .object([
                "description": .string("[numerator, denominator]"), "type": .string("array"),
                "prefixItems": .array([integer("Numerator", minimum: 1), integer("Denominator", minimum: 1)]),
                "minItems": .integer(2), "maxItems": .integer(2),
            ]),
            "media": .object(fields(
                "A source file, referenced by path, never copied", required: ["id", "path", "fps", "frames"],
                properties: [
                    "id": string("Stable media ID", minLength: 1),
                    "path": string("Relative to the project folder, or @assets/… in the workspace", minLength: 1, pattern: "^[^/]"),
                    "kind": enumeration("Media kind; an image is held for as long as its items last (frames is the limit)",
                                        ["video", "audio", "image"]),
                    "fps": ref("rational"), "frames": integer("Length in source frames", minimum: 1),
                    "width": integer("Pixels", minimum: 1, maximum: 16384),
                    "height": integer("Pixels", minimum: 1, maximum: 16384),
                    "hasAudio": boolean("Whether the file has sound"),
                    "alpha": boolean("A movie with an alpha channel (a video sticker); previewed without a proxy"),
                    TransitionPreset.soundLibraryField: string("The library item (scope:id) it was copied from"),
                ])),
            "track": track,
            "item": .object(item),
            "color": .object(group("color", "Color grade; on an adjustment item it applies to every layer below", extra: [
                "lut": .object(["description": .string("LUT ID from luts[]"), "type": .array([.string("string"), .string("null")])]),
            ])),
            "marker": .object(fields(
                "A marker; kind section starts a named section", required: ["at", "kind", "label"],
                properties: [
                    "id": string("Stable ID"), "at": integer("Timeline frame", minimum: 0), "kind": string("Marker kind", minLength: 1),
                    "label": string("Label", minLength: 1, maxLength: 120),
                ])),
            "transition": .object(fields(
                "A transition between two adjacent clips on a video layer",
                required: ["id", "kind", "from", "to", "duration"],
                properties: [
                    "id": string("Stable ID", minLength: 1),
                    "kind": enumeration("Transition kind", TimelineTransition.renderedKinds),
                    "from": string("Outgoing item ID"), "to": string("Incoming item ID"),
                    "duration": integer("Timeline frames", minimum: 1),
                    "easing": enumeration("How the tween runs; linear when absent", TimelineTransition.easings),
                ])),
            "lut": .object(fields(
                "A .cube file in the project luts folder", required: ["id", "name", "path", "size"],
                properties: [
                    "id": string("Stable ID", minLength: 1), "name": string("Display name", minLength: 1, maxLength: 120),
                    "path": string("luts/<file>.cube", pattern: "^luts/.+\\.cube$"),
                    "size": integer("Cube dimension", minimum: 2, maximum: 64),
                    ColorLUT.libraryHashField: string("SHA-256 of the library look's .cube it was copied from"),
                    ColorLUT.libraryItemField: string("The library look (scope:id) it was copied from"),
                ])),
            "look": .object(fields(
                "A reusable color grade", required: ["id", "title", "color"],
                properties: [
                    "id": string("Unique among built-in and custom looks", pattern: StyleCatalog.idPattern),
                    "title": string("Display name", minLength: 1, maxLength: 120), "color": ref("color"),
                ])),
            "styleKit": .object(fields(
                "A one-shot recipe: a full-length adjustment with a look plus a caption preset",
                required: ["id", "title", "look", "captionPreset"],
                properties: [
                    "id": string("Unique among built-in and custom kits", pattern: StyleCatalog.idPattern),
                    "title": string("Display name", minLength: 1, maxLength: 120),
                    "look": string("Built-in or custom look ID"),
                    "captionPreset": enumeration("Text preset given to captions", TextPreset.all),
                ])),
            "audio": audioSchema,
        ]
    }

    private static var track: JSONValue {
        var value = fields(
            "A layer. Items never overlap on one layer.", required: ["id", "kind", "role", "name", "items"],
            properties: [
                "id": string("Stable layer ID", minLength: 1), "kind": enumeration("Layer kind", TrackKind.all),
                "role": .object([
                    "type": .string("string"), "minLength": .integer(1),
                    "description": .string("Semantic role; any nonempty value, these are assigned by BashCut"),
                    "examples": .array(TrackRole.known.map(JSONValue.string)),
                ]),
                "name": string("Display name", minLength: 1),
                "magnetic": boolean("Inserts append after the last item; drags reorder and compact"),
                "hidden": boolean("Visual layers only: left out of preview and export"),
                "muted": boolean("Audio layers only: silent, and its speech stops ducking music"),
                "locked": boolean("Items cannot change until unlocked"),
                "duckingEnabled": boolean("Music layers: suspend ducking without losing the level"),
                "duckUnderSpeechDb": number("Music layers: level under speech", -60...0),
                "duckAttackFrames": integer("Music layers: ramp in", minimum: 0, maximum: 10_000),
                "duckReleaseFrames": integer("Music layers: ramp out", minimum: 0, maximum: 10_000),
                "items": array("Items, in any order", of: ref("item")),
            ])
        // What an item carries depends on its layer's kind.
        func items(_ rule: JSONValue) -> JSONValue {
            .object(["properties": .object(["items": .object(["items": rule])])])
        }
        func when(_ kinds: [String], _ rule: JSONValue) -> JSONValue {
            .object([
                "if": .object(["properties": .object(["kind": .object(["enum": .array(kinds.map(JSONValue.string))])])]),
                "then": items(rule),
            ])
        }
        let requires = { (key: String) in JSONValue.object(["required": .array([.string(key)])]) }
        value["allOf"] = .array([
            when([TrackKind.video, TrackKind.audio], requires("media")),
            when([TrackKind.text], requires("text")),
            when([TrackKind.adjustment], .object(["not": .object(["anyOf": .array([requires("media"), requires("text")])])])),
        ])
        return .object(value)
    }

    private static var item: [String: JSONValue] {
        var properties: [String: JSONValue] = [
            "id": string("Stable item ID, unique in the project", minLength: 1),
            "at": integer("Start, in timeline frames", minimum: 0),
            "dur": integer("Length, in timeline frames", minimum: 1),
            "in": integer("Source in-point, in media frames", minimum: 0),
            "media": string("Media ID (video and audio layers)"),
            "text": string("Caption or title text (text layers)"),
            "textPreset": enumeration("Text preset (text layers); default bold-outline", TextPreset.all),
            "freezeFrame": integer("Video: source frame held for the whole item", minimum: 0),
            "reframePreset": string("Framing preset ID, or custom"),
            "linkedAudio": string("Video: ID of its linked sound item"),
            "linkedVideo": string("Audio: ID of its linked picture item"),
            EffectRecipe.soundField: string("Audio: the clip whose effect preset placed this sound; applying it again replaces it"),
            EffectRecipe.textField: string("Text: the clip whose effect preset placed this text; applying it again replaces it"),
            "speedCurve": .object([
                "type": .string("array"), "minItems": .integer(2), "maxItems": .integer(SpeedCurve.maximumPoints),
                "description": .string(
                    "Speed ramp: points from t 0 (clip start) to t 1 (clip end), speed linear between them; "
                        + "speed then holds the curve's average. Set with setSpeedCurve."),
                "items": .object([
                    "type": .string("object"), "required": .array([.string("t"), .string("speed")]),
                    "properties": .object([
                        "t": .object(["type": .string("number"), "minimum": .integer(0), "maximum": .integer(1)]),
                        "speed": .object([
                            "type": .string("number"), "minimum": .number(Project.speedRange.lowerBound),
                            "maximum": .number(Project.speedRange.upperBound),
                        ]),
                    ]),
                ]),
            ]),
            "reversed": .object([
                "type": .string("object"),
                "description": .string("Set by clip reverse: the original media and in-point, restored by reversing again"),
                "properties": .object(["media": string("Original media ID"), "in": integer("Original in-point", minimum: 0)]),
            ]),
            "keyframes": .object([
                "type": .string("object"),
                "description": .string(
                    "Animation (video, text and audio layers; audio animates volume only): property → keys sorted by "
                        + "frame, counted from the item's start; "
                        + "values between keys follow each key's ease, and hold before the first and after the last key"),
                "additionalProperties": .bool(false),
                "properties": .object(Dictionary(uniqueKeysWithValues: ItemMotion.ranges.map { name, range in
                    (name, .object([
                        "type": .string("array"), "minItems": .integer(1), "maxItems": .integer(1000),
                        "description": .string(ItemMotion.summaries[name] ?? name),
                        "items": .object([
                            "type": .string("object"), "required": .array([.string("frame"), .string("value")]),
                            "properties": .object([
                                "frame": .object(["type": .string("integer")]),
                                "value": .object([
                                    "type": .string("number"), "minimum": .number(range.lowerBound),
                                    "maximum": .number(range.upperBound),
                                ]),
                                "ease": enumeration("Change to the next key; default inOut",
                                                    ItemMotion.Ease.allCases.map(\.rawValue)),
                            ]),
                        ]),
                    ]))
                })),
            ]),
            "words": .object([
                "type": .string("array"), "maxItems": .integer(CaptionWords.maximumWords),
                "description": .string(
                    "Text: timing of each word of the text (split at white space), in frames from the item's start; "
                        + "set by captions generate when the provider returns word timings"),
                "items": .object([
                    "type": .string("object"), "required": .array([.string("text"), .string("at"), .string("dur")]),
                    "properties": .object([
                        "text": string("The word"), "at": .object(["type": .string("integer")]),
                        "dur": integer("Frames", minimum: 1),
                    ]),
                ]),
            ]),
            "wordStyle": enumeration(
                "Text: show the words as they are spoken (highlight the current word, karaoke fill, or reveal); "
                    + "timings come from words, or are estimated", CaptionWords.styles),
            "styleKit": string("Adjustment: the style kit that added it; the next kit replaces it"),
            "tag": .object([
                "type": .string("object"), "description": .string("Editorial tags"),
                "properties": .object([
                    "role": enumeration("Speech coverage role", ["speech", "broll", "underVO"]),
                    "section": string("Section name"),
                ]),
            ]),
            "color": ref("color"),
        ]
        for name in ItemProperty.groups where name != "color" {
            let summaries = [
                "transform": "Framing",
                "crop": "Video picture: the visible part of the source frame (the picture keeps its place; zoom and pan move it)",
            ]
            properties[name] = .object(group(name, summaries[name] ?? "Text style overrides"))
        }
        for property in ItemProperty.all where property.group == nil {
            properties[property.key] = schema(for: property)
        }
        return fields("A timeline item; see the layer rules for which fields it needs", required: ["id", "at", "dur"],
                      properties: properties)
    }

    private static func group(_ name: String, _ summary: String, extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var properties = extra
        for property in ItemProperty.all where property.group == name { properties[property.key] = schema(for: property) }
        return fields(summary, required: [], properties: properties)
    }

    private static func schema(for property: ItemProperty) -> JSONValue {
        switch property.rule {
        case .number(let range): number(property.summary, range)
        case .integer(let range): integer(property.summary, minimum: range.lowerBound, maximum: range.upperBound)
        case .boolean: boolean(property.summary)
        case .text(let maxLength): string(property.summary, minLength: 1, maxLength: maxLength)
        case .color: string(property.summary, pattern: ItemProperty.Rule.colorPattern)
        }
    }

    // MARK: Builders

    static func fields(
        _ summary: String, required: [String], properties: [String: JSONValue]
    ) -> [String: JSONValue] {
        var value: [String: JSONValue] = [
            "type": .string("object"), "description": .string(summary), "properties": .object(properties),
        ]
        if !required.isEmpty { value["required"] = .array(required.map(JSONValue.string)) }
        return value
    }

    static func object(_ summary: String, required: [String], properties: [String: JSONValue]) -> JSONValue {
        .object(fields(summary, required: required, properties: properties))
    }

    static func ref(_ name: String) -> JSONValue { .object(["$ref": .string("#/$defs/\(name)")]) }

    static func array(_ summary: String, of items: JSONValue, minItems: Int? = nil, maxItems: Int? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("array"), "description": .string(summary), "items": items]
        if let minItems { value["minItems"] = .integer(minItems) }
        if let maxItems { value["maxItems"] = .integer(maxItems) }
        return .object(value)
    }

    static func string(
        _ summary: String, minLength: Int? = nil, maxLength: Int? = nil, pattern: String? = nil
    ) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("string"), "description": .string(summary)]
        if let minLength { value["minLength"] = .integer(minLength) }
        if let maxLength { value["maxLength"] = .integer(maxLength) }
        if let pattern { value["pattern"] = .string(pattern) }
        return .object(value)
    }

    static func enumeration(_ summary: String, _ values: [String]) -> JSONValue {
        .object([
            "type": .string("string"), "description": .string(summary), "enum": .array(values.map(JSONValue.string)),
        ])
    }

    static func integer(_ summary: String, minimum: Int? = nil, maximum: Int? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("integer"), "description": .string(summary)]
        if let minimum { value["minimum"] = .integer(minimum) }
        if let maximum { value["maximum"] = .integer(maximum) }
        return .object(value)
    }

    static func number(_ summary: String, _ range: ClosedRange<Double>) -> JSONValue {
        .object([
            "type": .string("number"), "description": .string(summary),
            "minimum": bound(range.lowerBound), "maximum": bound(range.upperBound),
        ])
    }

    private static func bound(_ value: Double) -> JSONValue {
        value.rounded() == value && abs(value) < 1e15 ? .integer(Int(value)) : .number(value)
    }

    static func boolean(_ summary: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(summary)])
    }
}
