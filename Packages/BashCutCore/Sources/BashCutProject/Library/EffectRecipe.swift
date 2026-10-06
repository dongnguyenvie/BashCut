import Foundation

/// An effect preset's params as a recipe (#76): named parameters and steps that reuse the clip edits BashCut already
/// has, applied together as one undo step.
///
/// `params.steps` is a list of `{"op": …}` objects run in order on the target clip (or the part of it a range splits
/// off):
/// - `motion`: `preset` (a `MotionPreset` sized to the clip), or `focus` (`[x, y, w, h]` as fractions 0–1 of the
///   source picture) with an optional `focusTo` and `ease`, like `clip motion --focus`.
/// - `keyframes`: `keys` `{property: [{t | frame, value, ease?}]}`, replacing those properties' keys and keeping the
///   others. `t` is a position from 0 (first frame) to 1 (last frame), so keys scale with the clip; `frame` counts
///   timeline frames from the start (negative: from the end).
/// - `speed` (`speed`, `keepDuration?`) and `speedCurve` (`preset` or `points` `[[t, speed]…]`, `keepDuration?`).
/// - `reverse`: plays the clip backwards (a clip already reversed stays as it is).
/// - `freeze`: holds the frame at `t` or `frame` (the first by default) over the whole target.
/// - `patch`: item properties set as they are (`transform`, `opacity`, …).
/// - `sfx`: a sound on an SFX layer at `t` or `frame`: `sfx` names an audio library item, or without it the preset's
///   own file; `volumeDb` optional.
/// - `text`: a text item over the clip from `t` or `frame` for `duration` frames (to the clip's end by default), with
///   `text` and `textPreset`.
///
/// `params.parameters` declares named numbers `{name: {default, min, max, label?}}`; a step value written `"$name"`
/// takes the parameter's value (the default, or an override when applying). Frame values must stay integers.
///
/// An old effect preset with only `params.patch` (item properties) is a recipe of that one patch step, applied as
/// before.
public struct EffectRecipe: Sendable, Equatable {
    public static let maximumSteps = 32
    public static let maximumParameters = 16
    /// The item field that marks a sound effect a recipe placed, with the ID of the clip it belongs to.
    public static let soundField = "effectSFX"
    /// The item field that marks a text item a recipe placed, with the ID of the clip it belongs to.
    public static let textField = "effectText"
    /// The key of the preset's own file among the sounds given to the plan.
    public static let ownSound = "file"
    public static let stepKinds = ["motion", "keyframes", "speed", "speedCurve", "reverse", "freeze", "patch", "sfx", "text"]

    public struct Parameter: Sendable, Equatable {
        public var name: String
        public var value: Double
        public var minimum: Double
        public var maximum: Double
        public var label: String?

        public init(_ name: String, value: Double, minimum: Double, maximum: Double, label: String? = nil) {
            self.name = name
            self.value = value
            self.minimum = minimum
            self.maximum = maximum
            self.label = label
        }

        var json: JSONValue {
            var fields: [String: JSONValue] = [
                "default": EffectRecipe.number(value), "min": EffectRecipe.number(minimum), "max": EffectRecipe.number(maximum),
            ]
            if let label { fields["label"] = .string(label) }
            return .object(fields)
        }
    }

    /// Where in the target a step happens.
    public enum Position: Sendable, Equatable {
        /// 0 is the first frame, 1 the last.
        case fraction(Double)
        /// Frames from the start; negative counts from the end (-1 is the last frame).
        case frame(Int)

        /// The frame from the target's start for a target of `length` frames (not clamped).
        public func frame(length: Int) -> Int {
            switch self {
            case .fraction(let t): Int((t * Double(max(0, length - 1))).rounded())
            case .frame(let frame): frame < 0 ? length + frame : frame
            }
        }
    }

    public struct Key: Sendable, Equatable {
        public var position: Position
        public var value: Double
        public var ease: ItemMotion.Ease
    }

    /// A step with its parameters filled in.
    public enum Step: Sendable, Equatable {
        case motion(preset: String)
        case focus(MotionFocus.Region, to: MotionFocus.Region?, ease: ItemMotion.Ease)
        case keyframes([String: [Key]])
        case speed(Double, keepDuration: Bool)
        case speedCurve(SpeedCurve, keepDuration: Bool)
        case reverse
        case freeze(Position)
        case patch([String: JSONValue])
        case sfx(source: String?, at: Position, volumeDb: Double?)
        case text(String, preset: String, at: Position, duration: Int?)
    }

    public var parameters: [Parameter]
    /// The steps as stored, `"$name"` references included.
    public var steps: [[String: JSONValue]]
    /// Made from an old `params.patch`; `params` writes it back that way.
    public private(set) var isLegacyPatch = false

    public init(parameters: [Parameter] = [], steps: [[String: JSONValue]]) {
        self.parameters = parameters.sorted { $0.name < $1.name }
        self.steps = steps
    }

    /// Reads and checks `params` (every step, with the parameters' defaults); `label` starts each error message.
    public init(params: [String: JSONValue], label: String = "effect preset") throws {
        if let value = params["steps"] {
            guard case .array(let list) = value, (1...Self.maximumSteps).contains(list.count) else {
                throw ProjectError.invalid("\(label): params.steps must list 1–\(Self.maximumSteps) steps")
            }
            steps = try list.enumerated().map { index, step in
                guard case .object(let fields) = step else {
                    throw ProjectError.invalid("\(label): params.steps[\(index)] must be an object")
                }
                return fields
            }
        } else if case .object(let patch) = params["patch"] ?? .null, !patch.isEmpty {
            steps = [["op": .string("patch"), "patch": .object(patch)]]
            isLegacyPatch = true
        } else {
            throw ProjectError.invalid(
                "\(label): an effect preset needs params.steps (a recipe) or params.patch (the item properties it sets)")
        }
        parameters = try Self.parameters(params["parameters"], label: label)
        _ = try resolvedSteps(label: label)
    }

    /// The params as a library item stores them.
    public var params: [String: JSONValue] {
        if isLegacyPatch, let patch = steps.first?["patch"] { return ["patch": patch] }
        var params: [String: JSONValue] = ["steps": .array(steps.map(JSONValue.object))]
        if !parameters.isEmpty {
            params["parameters"] = .object(Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.json) }))
        }
        return params
    }

    /// Each parameter's value: its default, or the override. An unknown name or a value outside the parameter's range
    /// is an error.
    public func values(_ overrides: [String: Double] = [:]) throws -> [String: Double] {
        var values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })
        for (name, value) in overrides {
            guard let parameter = parameters.first(where: { $0.name == name }) else {
                let known = parameters.isEmpty ? "it has none" : "use " + parameters.map(\.name).joined(separator: ", ")
                throw ProjectError.invalid("Unknown effect parameter \(name); \(known)")
            }
            guard value.isFinite, (parameter.minimum...parameter.maximum).contains(value) else {
                throw ProjectError.invalid(
                    "Effect parameter \(name) must be between \(Self.text(parameter.minimum)) and \(Self.text(parameter.maximum))")
            }
            values[name] = value
        }
        return values
    }

    /// The steps with their parameters filled in and checked.
    public func resolvedSteps(_ overrides: [String: Double] = [:], label: String = "effect preset") throws -> [Step] {
        let values = try values(overrides)
        return try steps.enumerated().map { index, fields in
            let path = "\(label): params.steps[\(index)]"
            let resolved = try Self.resolve(.object(fields), values: values, path: path).object
            return try Self.step(resolved, path: path)
        }
    }

    /// Overrides written `name=value,name=value`, or as a JSON object.
    public static func overrides(_ text: String) throws -> [String: Double] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)), case .object(let fields) = json
            else { throw ProjectError.invalid("set must be a JSON object or name=value pairs") }
            return try fields.mapValues { value in
                guard let number = value.double else { throw ProjectError.invalid("set values must be numbers") }
                return number
            }
        }
        var values: [String: Double] = [:]
        for pair in trimmed.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, let number = Double(parts[1]) else {
                throw ProjectError.invalid("set must be name=value pairs, such as strength=1.5,frames=12")
            }
            values[parts[0]] = number
        }
        return values
    }

    // MARK: Reading

    private static let parameterPattern = "^[a-zA-Z][a-zA-Z0-9]{0,31}$"

    private static func parameters(_ value: JSONValue?, label: String) throws -> [Parameter] {
        guard let value else { return [] }
        guard case .object(let fields) = value, fields.count <= maximumParameters else {
            throw ProjectError.invalid("\(label): params.parameters must be an object of up to \(maximumParameters) parameters")
        }
        return try fields.keys.sorted().map { name in
            let path = "\(label): params.parameters.\(name)"
            guard name.range(of: parameterPattern, options: .regularExpression) != nil else {
                throw ProjectError.invalid("\(path): a name is a letter then letters or digits")
            }
            let entry = fields[name]?.object ?? [:]
            guard let value = entry["default"]?.double, let minimum = entry["min"]?.double, let maximum = entry["max"]?.double,
                [value, minimum, maximum].allSatisfy(\.isFinite), minimum <= value, value <= maximum
            else { throw ProjectError.invalid("\(path) needs numbers default, min and max with min ≤ default ≤ max") }
            if let label = entry["label"], label.string.map({ !$0.isEmpty && $0.count <= 60 }) != true {
                throw ProjectError.invalid("\(path).label must be 1–60 characters")
            }
            return Parameter(name, value: value, minimum: minimum, maximum: maximum, label: entry["label"]?.string)
        }
    }

    /// Replaces `"$name"` strings with the parameter's value (an integer when it is whole); text stays as written.
    private static func resolve(_ value: JSONValue, values: [String: Double], path: String) throws -> JSONValue {
        switch value {
        case .object(let fields):
            var resolved: [String: JSONValue] = [:]
            for (key, field) in fields { resolved[key] = key == "text" ? field : try resolve(field, values: values, path: path) }
            return .object(resolved)
        case .array(let list):
            return .array(try list.map { try resolve($0, values: values, path: path) })
        case .string(let text) where text.hasPrefix("$"):
            let name = String(text.dropFirst())
            guard name.range(of: parameterPattern, options: .regularExpression) != nil else { return value }
            guard let found = values[name] else { throw ProjectError.invalid("\(path) uses \(text), which is not a parameter") }
            return Self.number(found)
        default:
            return value
        }
    }

    static func number(_ value: Double) -> JSONValue {
        value.rounded() == value && abs(value) < 1e15 ? .integer(Int(value)) : .number(value)
    }

    private static func text(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

// MARK: Steps

extension EffectRecipe {
    // One case per step kind keeps each kind's fields together.
    // swiftlint:disable:next cyclomatic_complexity
    fileprivate static func step(_ fields: [String: JSONValue], path: String) throws -> Step {
        let op = fields["op"]?.string ?? ""
        switch op {
        case "motion":
            if let preset = fields["preset"] {
                guard let id = preset.string, MotionPreset.all.contains(where: { $0.id == id }) else {
                    throw ProjectError.invalid(
                        "\(path).preset must be one of \(MotionPreset.all.map(\.id).joined(separator: ", "))")
                }
                return .motion(preset: id)
            }
            guard let focus = fields["focus"] else { throw ProjectError.invalid("\(path): motion needs preset or focus") }
            return .focus(
                try region(focus, path: "\(path).focus"), to: try fields["focusTo"].map { try region($0, path: "\(path).focusTo") },
                ease: try ease(fields["ease"], path: path) ?? .easeInOut)
        case "keyframes":
            guard case .object(let properties) = fields["keys"] ?? .null, !properties.isEmpty else {
                throw ProjectError.invalid("\(path): keyframes needs keys {property: [{t or frame, value, ease?}]}")
            }
            var keys: [String: [Key]] = [:]
            for (property, list) in properties {
                guard let range = ItemMotion.ranges[property] else {
                    throw ProjectError.invalid(
                        "\(path).keys.\(property): use \(ItemMotion.ranges.keys.sorted().joined(separator: ", "))")
                }
                guard case .array(let entries) = list, (1...1000).contains(entries.count) else {
                    throw ProjectError.invalid("\(path).keys.\(property): expected 1–1000 keys")
                }
                keys[property] = try entries.map { entry in
                    let key = entry.object
                    guard let value = key["value"]?.double, value.isFinite, range.contains(value) else {
                        throw ProjectError.invalid("\(path).keys.\(property): each value must be a number in \(range)")
                    }
                    guard let at = try position(key, path: "\(path).keys.\(property)") else {
                        throw ProjectError.invalid("\(path).keys.\(property): each key needs t or frame")
                    }
                    return Key(position: at, value: value, ease: try ease(key["ease"], path: path) ?? .easeInOut)
                }
            }
            return .keyframes(keys)
        case "speed":
            guard let speed = fields["speed"]?.double, speed.isFinite, Project.speedRange.contains(speed) else {
                throw ProjectError.invalid("\(path).speed must be between 0.1 and 16")
            }
            return .speed(speed, keepDuration: try flag(fields["keepDuration"], path: path))
        case "speedCurve":
            return .speedCurve(try curve(fields, path: path), keepDuration: try flag(fields["keepDuration"], path: path))
        case "reverse":
            return .reverse
        case "freeze":
            return .freeze(try position(fields, path: path) ?? .frame(0))
        case "patch":
            guard case .object(let patch) = fields["patch"] ?? .null, !patch.isEmpty else {
                throw ProjectError.invalid("\(path): patch needs patch, the item properties it sets")
            }
            let timing: Set<String> = ["id", "media", "at", "dur", "in", "linkedAudio", "linkedVideo"]
            guard timing.isDisjoint(with: patch.keys) else {
                throw ProjectError.invalid("\(path).patch cannot set an item's identity or timing")
            }
            return .patch(patch)
        case "sfx":
            var source: String?
            if let value = fields["sfx"] {
                let id = value.string.map { $0.split(separator: ":", maxSplits: 1).last.map(String.init) ?? $0 }
                guard let id, id.range(of: StyleCatalog.idPattern, options: .regularExpression) != nil else {
                    throw ProjectError.invalid("\(path).sfx must be an audio library item ID")
                }
                source = value.string
            }
            return .sfx(source: source, at: try position(fields, path: path) ?? .frame(0), volumeDb: try volume(fields, path: path))
        case "text":
            guard let text = fields["text"]?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                text.count <= 500
            else { throw ProjectError.invalid("\(path).text must be 1–500 characters") }
            let preset = fields["textPreset"]?.string ?? "bold-outline"
            guard TextPreset.all.contains(preset) else {
                throw ProjectError.invalid("\(path).textPreset must be one of \(TextPreset.all.joined(separator: ", "))")
            }
            var duration: Int?
            if let value = fields["duration"] {
                guard let frames = value.int, frames >= 1 else {
                    throw ProjectError.invalid("\(path).duration must be a whole number of frames")
                }
                duration = frames
            }
            return .text(text, preset: preset, at: try position(fields, path: path) ?? .frame(0), duration: duration)
        default:
            throw ProjectError.invalid("\(path).op must be one of \(stepKinds.joined(separator: ", "))")
        }
    }

    /// `t` (a finite number) or `frame` (an integer), or nil when neither is given.
    private static func position(_ fields: [String: JSONValue], path: String) throws -> Position? {
        if let value = fields["t"] {
            guard let t = value.double, t.isFinite, (-10...10).contains(t) else {
                throw ProjectError.invalid("\(path): t must be a number, 0 at the start and 1 at the end")
            }
            return .fraction(t)
        }
        if let value = fields["frame"] {
            guard let frame = value.int, abs(frame) <= 2_000_000_000 else {
                throw ProjectError.invalid("\(path): frame must be a whole number of frames")
            }
            return .frame(frame)
        }
        return nil
    }

    private static func region(_ value: JSONValue, path: String) throws -> MotionFocus.Region {
        let numbers: [Double?] = switch value {
        case .array(let list): list.map(\.double)
        case .string(let text): text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        default: []
        }
        guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let width = numbers[2], let height = numbers[3],
            [x, y].allSatisfy({ (0...1).contains($0) }), [width, height].allSatisfy({ $0 > 0 && $0 <= 1 })
        else { throw ProjectError.invalid("\(path) must be [x, y, width, height] as fractions 0–1 of the picture") }
        return MotionFocus.Region(x: x, y: y, width: width, height: height)
    }

    private static func ease(_ value: JSONValue?, path: String) throws -> ItemMotion.Ease? {
        guard let value else { return nil }
        guard let ease = value.string.flatMap(ItemMotion.Ease.init(rawValue:)) else {
            throw ProjectError.invalid(
                "\(path): ease must be one of \(ItemMotion.Ease.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return ease
    }

    private static func flag(_ value: JSONValue?, path: String) throws -> Bool {
        guard let value else { return false }
        guard let flag = value.bool else { throw ProjectError.invalid("\(path).keepDuration must be true or false") }
        return flag
    }

    private static func volume(_ fields: [String: JSONValue], path: String) throws -> Double? {
        guard let value = fields["volumeDb"] else { return nil }
        guard let volume = value.double, volume.isFinite, (-60...12).contains(volume) else {
            throw ProjectError.invalid("\(path).volumeDb must be between -60 and 12")
        }
        return volume
    }

    private static func curve(_ fields: [String: JSONValue], path: String) throws -> SpeedCurve {
        if let preset = fields["preset"] {
            guard let curve = preset.string.flatMap(SpeedCurve.preset) else {
                throw ProjectError.invalid(
                    "\(path).preset must be one of \(SpeedCurve.presets.map(\.id).joined(separator: ", "))")
            }
            return curve
        }
        guard case .array(let points) = fields["points"] ?? .null else {
            throw ProjectError.invalid("\(path): speedCurve needs preset or points [[t, speed], …]")
        }
        let objects: [JSONValue] = points.map { point in
            if case .array(let pair) = point, pair.count == 2 { return .object(["t": pair[0], "speed": pair[1]]) }
            return point
        }
        do { return try SpeedCurve(json: .array(objects)) } catch {
            throw ProjectError.invalid("\(path): \(error.localizedDescription)")
        }
    }
}
