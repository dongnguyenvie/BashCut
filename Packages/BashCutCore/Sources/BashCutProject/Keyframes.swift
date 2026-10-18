import Foundation

/// Animation of an item's picture and sound over its length: the item field `keyframes`, an object from property name to a
/// list of `{"frame", "value", "ease"?}` sorted by frame. Frames count from the item's start (0 = its first frame)
/// and move with the picture when the item is split or its start is trimmed. Before the first key the property
/// keeps the first value, after the last key the last value. `ease` shapes the change from that key to the next.
///
/// Properties: `zoom` (scale over the fitted or filled size, like `transform.zoom`), `pan` and `tilt` (offset in
/// output pixels, like `transform.pan`/`tilt`; tilt is up), `rotation` (degrees, counterclockwise) and `opacity`
/// animate the picture; `volume` (gain in dB, like `volumeDb`) the sound. A property with keys replaces the item's
/// static value; the others keep it. On text items, zoom scales the text around its own position. Audio items have
/// only `volume`, text items have no `volume` (see `properties(onTrackKind:)`). Numeric style fields animate too
/// (flexibility audit C13): `color.exposure`, `color.contrast`, `color.saturation` and `color.lutStrength` on clips and
/// adjustment layers, `textStyle.size`, `positionX`, `positionY`, `strokeWidth`, `lineHeight` and `tracking` on text,
/// and `crop.left`, `right`, `top`, `bottom` and `radius` (rounded corners) on clips and images.
public struct ItemMotion: Sendable, Equatable {
    /// How a value changes from one key to the next, and how a transition's tween runs (flexibility audit C6): the
    /// named curves, or `cubic-bezier(x1, y1, x2, y2)` like CSS (x1 and x2 in 0…1).
    public enum Ease: Sendable, Hashable, CaseIterable, RawRepresentable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        /// Keeps this key's value until the next key.
        case hold
        case cubicBezier(Double, Double, Double, Double)

        /// The named curves (pickers and choices); any `cubic-bezier(…)` is valid too.
        public static let allCases: [Ease] = [.linear, .easeIn, .easeOut, .easeInOut, .hold]

        public init?(rawValue: String) {
            switch rawValue {
            case "linear": self = .linear
            case "in": self = .easeIn
            case "out": self = .easeOut
            case "inOut": self = .easeInOut
            case "hold": self = .hold
            default:
                let text = rawValue.replacingOccurrences(of: " ", with: "")
                guard text.hasPrefix("cubic-bezier("), text.hasSuffix(")") else { return nil }
                let numbers = text.dropFirst(13).dropLast().split(separator: ",").compactMap { Double($0) }
                guard numbers.count == 4, numbers.allSatisfy(\.isFinite), (0...1).contains(numbers[0]),
                    (0...1).contains(numbers[2]), (-10...10).contains(numbers[1]), (-10...10).contains(numbers[3])
                else { return nil }
                self = .cubicBezier(numbers[0], numbers[1], numbers[2], numbers[3])
            }
        }

        public var rawValue: String {
            switch self {
            case .linear: "linear"
            case .easeIn: "in"
            case .easeOut: "out"
            case .easeInOut: "inOut"
            case .hold: "hold"
            case .cubicBezier(let x1, let y1, let x2, let y2):
                "cubic-bezier(" + [x1, y1, x2, y2].map { String(format: "%g", $0) }.joined(separator: ",") + ")"
            }
        }

        /// The names and the bezier form, for messages and descriptions.
        public static let summary = allCases.map(\.rawValue).joined(separator: ", ") + " or cubic-bezier(x1,y1,x2,y2)"

        public func apply(_ t: Double) -> Double {
            switch self {
            case .linear: t
            case .easeIn: t * t * t
            case .easeOut: 1 - pow(1 - t, 3)
            case .easeInOut: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            case .hold: 0
            case .cubicBezier(let x1, let y1, let x2, let y2): Self.bezier(t, x1, y1, x2, y2)
            }
        }

        /// y at the curve point whose x is `x`: Newton steps on x(s), then bisection when the slope is flat.
        static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
            let t = min(1, max(0, x))
            let curve = { (s: Double, p1: Double, p2: Double) in
                3 * (1 - s) * (1 - s) * s * p1 + 3 * (1 - s) * s * s * p2 + s * s * s
            }
            var s = t
            for _ in 0..<8 {
                let error = curve(s, x1, x2) - t
                if abs(error) < 1e-7 { return curve(s, y1, y2) }
                let slope = 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2)
                if abs(slope) < 1e-6 { break }
                s = min(1, max(0, s - error / slope))
            }
            var low = 0.0, high = 1.0
            s = t
            for _ in 0..<40 {
                if curve(s, x1, x2) < t { low = s } else { high = s }
                s = (low + high) / 2
            }
            return curve(s, y1, y2)
        }
    }

    public struct Key: Sendable, Equatable {
        public var frame: Int
        public var value: Double
        public var ease: Ease

        public init(frame: Int, value: Double, ease: Ease = .easeInOut) {
            self.frame = frame
            self.value = value
            self.ease = ease
        }
    }

    /// Style fields keyframes can drive, as `group.field` paths with their ranges.
    public static let colorProperties: [String: ClosedRange<Double>] = Dictionary(
        uniqueKeysWithValues: ColorGrade.ranges.map { ("color." + $0.key, $0.range) })
    public static let textStyleProperties: [String: ClosedRange<Double>] = [
        "textStyle.size": 0.005...1, "textStyle.positionX": 0...1, "textStyle.positionY": 0...1,
        "textStyle.strokeWidth": 0...50, "textStyle.lineHeight": 0.5...4, "textStyle.tracking": -0.5...2,
    ]

    /// The visible part of a clip's picture (`crop.*`): sides as shares hidden, radius as a share of the shorter side.
    public static let cropProperties: [String: ClosedRange<Double>] = [
        "crop.left": 0...0.95, "crop.right": 0...0.95, "crop.top": 0...0.95, "crop.bottom": 0...0.95, "crop.radius": 0...0.5,
    ]

    public static let ranges: [String: ClosedRange<Double>] = [
        "zoom": 0.01...100, "pan": -65536...65536, "tilt": -65536...65536, "rotation": -3600...3600, "opacity": 0...1,
        "volume": -120...24,
    ].merging(colorProperties) { $1 }.merging(textStyleProperties) { $1 }.merging(cropProperties) { $1 }
    public static let summaries = [
        "zoom": "Scale over the fitted or filled size (1 = unchanged)",
        "pan": "Horizontal offset in output pixels",
        "tilt": "Vertical offset in output pixels, up",
        "rotation": "Rotation in degrees, counterclockwise",
        "opacity": "Opacity, 0 to 1",
        "volume": "Gain in dB (0 = unchanged), like volumeDb; audio and clips with sound",
    ].merging(colorProperties.keys.map { ($0, "Like the item's \($0); clips and adjustment layers") }) { $1 }
        .merging(textStyleProperties.keys.map { ($0, "Like the item's \($0); text") }) { $1 }
        .merging(cropProperties.keys.map { ($0, "Like the item's \($0); video clips and images") }) { $1 }
    /// The properties that move the picture, in the order the Inspector shows them.
    public static let pictureProperties = ["zoom", "pan", "tilt", "rotation", "opacity"]

    /// The properties an item on a layer of `kind` can animate.
    public static func properties(onTrackKind kind: String) -> [String] {
        switch kind {
        case TrackKind.video: pictureProperties + ["volume"] + colorProperties.keys.sorted() + cropProperties.keys.sorted()
        case TrackKind.text: pictureProperties + textStyleProperties.keys.sorted()
        case TrackKind.adjustment: colorProperties.keys.sorted()
        case TrackKind.audio: ["volume"]
        default: []
        }
    }

    public var keys: [String: [Key]]

    public init(keys: [String: [Key]]) { self.keys = keys }

    public init(json: JSONValue) throws {
        guard case .object(let properties) = json else { throw ProjectError.invalid("keyframes: expected an object") }
        var keys: [String: [Key]] = [:]
        for (name, value) in properties {
            guard let range = Self.ranges[name] else {
                throw ProjectError.invalid(
                    "keyframes.\(name): unknown property; use \(Self.ranges.keys.sorted().joined(separator: ", "))")
            }
            guard case .array(let list) = value, (1...1000).contains(list.count) else {
                throw ProjectError.invalid("keyframes.\(name): expected 1–1000 keys")
            }
            var parsed: [Key] = []
            for entry in list {
                let fields = entry.object
                guard let frame = fields["frame"]?.int, (-2_000_000_000...2_000_000_000).contains(frame),
                    let number = fields["value"]?.double, number.isFinite, range.contains(number)
                else {
                    throw ProjectError.invalid(
                        "keyframes.\(name): each key needs an integer frame and a value in \(range)")
                }
                var ease = Ease.easeInOut
                if let text = fields["ease"]?.string {
                    guard let known = Ease(rawValue: text) else {
                        throw ProjectError.invalid("keyframes.\(name): ease must be one of \(Ease.summary)")
                    }
                    ease = known
                }
                parsed.append(Key(frame: frame, value: number, ease: ease))
            }
            guard zip(parsed, parsed.dropFirst()).allSatisfy({ $0.frame < $1.frame }) else {
                throw ProjectError.invalid("keyframes.\(name): frames must increase")
            }
            keys[name] = parsed
        }
        self.keys = keys
    }

    public var json: JSONValue {
        .object(keys.mapValues { list in
            .array(list.map { key in
                var fields: [String: JSONValue] = ["frame": .integer(key.frame), "value": .number(key.value)]
                if key.ease != .easeInOut { fields["ease"] = .string(key.ease.rawValue) }
                return .object(fields)
            })
        })
    }

    public var isEmpty: Bool { keys.values.allSatisfy(\.isEmpty) }

    /// Every frame that has a key on any property, sorted and without repeats; the timeline marks these on the clip.
    public var keyedFrames: [Int] { Set(keys.values.joined().map(\.frame)).sorted() }

    /// The animated value of `property` at `frame` (from the item's start; fractions allowed), or nil when it has
    /// no keys.
    public func value(_ property: String, at frame: Double) -> Double? {
        guard let list = keys[property], let first = list.first, let last = list.last else { return nil }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        guard let next = list.firstIndex(where: { Double($0.frame) > frame }), next > 0 else { return last.value }
        let from = list[next - 1], to = list[next]
        let t = (frame - Double(from.frame)) / Double(to.frame - from.frame)
        return from.value + (to.value - from.value) * from.ease.apply(t)
    }

    /// Only the keys that move the picture; nil when there are none (the compositor then draws the item still).
    public var picture: ItemMotion? {
        let motion = ItemMotion(keys: keys.filter { Self.pictureProperties.contains($0.key) && !$0.value.isEmpty })
        return motion.isEmpty ? nil : motion
    }

    /// Only the keys of style fields (`color.*`, `textStyle.*`, `crop.*`); nil when there are none.
    public var style: ItemMotion? {
        let motion = ItemMotion(keys: keys.filter { $0.key.contains(".") && !$0.value.isEmpty })
        return motion.isEmpty ? nil : motion
    }

    /// Whether any `crop.*` field has keys (the compositor then cuts the picture anew at each frame).
    public var keysCrop: Bool { keys.contains { $0.key.hasPrefix("crop.") && !$0.value.isEmpty } }

    /// `fields` with each keyed style field set to its value at `frame` (from the item's start).
    public func styled(_ fields: [String: JSONValue], at frame: Double) -> [String: JSONValue] {
        var fields = fields
        for property in keys.keys where property.contains(".") {
            let parts = property.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, let value = value(property, at: frame) else { continue }
            var group = fields[parts[0]]?.object ?? [:]
            group[parts[1]] = .number((value * 10_000).rounded() / 10_000)
            fields[parts[0]] = .object(group)
        }
        return fields
    }

    /// The same animation with every key `offset` frames later (negative: earlier).
    public func shifted(by offset: Int) -> ItemMotion {
        ItemMotion(keys: keys.mapValues { $0.map { Key(frame: $0.frame + offset, value: $0.value, ease: $0.ease) } })
    }
}

extension Item {
    /// Fields a `setProperties` patch removes when it sets them to null.
    public static let removableFields: Set<String> = [
        "freezeFrame", "keyframes", "words", "wordStyle", "brandRoles", "backdrop", "enter", "exit",
    ]

    /// The item's keyframes; nil when it has none (or they are invalid, which validation rejects).
    public var motion: ItemMotion? {
        guard let value = fields["keyframes"], let motion = try? ItemMotion(json: value), !motion.isEmpty else {
            return nil
        }
        return motion
    }

    /// The keys that move the item's picture, if any.
    public var pictureMotion: ItemMotion? { motion?.picture }

    /// Moves time-based content (keyframes, word timings) after the item's picture moved by `offset` frames against
    /// its start: splitting off the right part, or trimming the start.
    mutating func shiftTimedContent(by offset: Int) {
        guard offset != 0 else { return }
        if let motion { fields["keyframes"] = motion.shifted(by: offset).json }
        if case .array(let words) = fields["words"] {
            fields["words"] = .array(words.map { word in
                var entry = word.object
                if let at = entry["at"]?.int { entry["at"] = .integer(at + offset) }
                return .object(entry)
            })
        }
    }
}

/// Keyframes as data, independent of an item's length and frame size (C7): `{property: [key]}` like `keyframes`, with
/// each key's time as `t` (0–1 of the item's length, 1 = its last frame) or `s` (seconds from the start; negative:
/// from the end) instead of `frame`, and `value` a number or `{"width": f}` / `{"height": f}` (a fraction of the
/// frame's size, for pan and tilt). `ease` as on keyframes. Keys are clamped into the item and kept increasing.
public struct MotionTemplate: Sendable, Equatable {
    public let json: JSONValue

    public init(json: JSONValue, label: String = "animation") throws {
        guard case .object(let properties) = json, !properties.isEmpty else {
            throw ProjectError.invalid("\(label): expected an object of property to keys")
        }
        for (name, value) in properties {
            guard ItemMotion.ranges[name] != nil else {
                throw ProjectError.invalid(
                    "\(label).\(name): unknown property; use \(ItemMotion.ranges.keys.sorted().joined(separator: ", "))")
            }
            guard case .array(let keys) = value, (1...1000).contains(keys.count) else {
                throw ProjectError.invalid("\(label).\(name): expected 1–1000 keys")
            }
            for key in keys {
                let fields = key.object
                let time = fields["t"]?.double.map { (0...1).contains($0) } ?? (fields["s"]?.double?.isFinite == true)
                let number = fields["value"]?.double ?? fields["value"]?.object["width"]?.double
                    ?? fields["value"]?.object["height"]?.double
                guard time, number?.isFinite == true else {
                    throw ProjectError.invalid(
                        "\(label).\(name): each key needs t (0–1) or s (seconds) and a number value (or {width|height: f})")
                }
                if let ease = fields["ease"]?.string, ItemMotion.Ease(rawValue: ease) == nil {
                    throw ProjectError.invalid(
                        "\(label).\(name): ease must be one of \(ItemMotion.Ease.allCases.map(\.rawValue).joined(separator: ", "))")
                }
            }
        }
        self.json = json
    }

    /// The keys for an item of `duration` frames in a `width`×`height` frame at `fps`.
    public func motion(duration: Int, width: Int, height: Int, fps: FrameRate) throws -> ItemMotion {
        let end = max(1, duration - 1)
        var keys: [String: [ItemMotion.Key]] = [:]
        for (name, value) in json.object {
            var list: [ItemMotion.Key] = []
            for entry in value.array {
                let fields = entry.object
                var frame: Int
                if let t = fields["t"]?.double {
                    frame = Int((t * Double(end)).rounded())
                } else {
                    let seconds = fields["s"]?.double ?? 0
                    let offset = Int((abs(seconds) * fps.value).rounded())
                    frame = seconds < 0 ? end - offset : offset
                }
                frame = min(max(0, frame), end)
                if let last = list.last?.frame { frame = max(frame, last + 1) }
                let number = Self.value(fields["value"], width: width, height: height)
                let ease = fields["ease"]?.string.flatMap(ItemMotion.Ease.init(rawValue:)) ?? .easeInOut
                list.append(ItemMotion.Key(frame: frame, value: number, ease: ease))
            }
            keys[name] = list
        }
        return try ItemMotion(json: ItemMotion(keys: keys).json)
    }

    /// A key's value: a number, or a fraction of the frame's width or height.
    private static func value(_ raw: JSONValue?, width: Int, height: Int) -> Double {
        if let number = raw?.double { return number }
        let fractions = raw?.object ?? [:]
        if let fraction = fractions["width"]?.double { return fraction * Double(width) }
        return (fractions["height"]?.double ?? 0) * Double(height)
    }
}

/// Ready-made animations for `clip motion` and the Inspector's Animation menu: `MotionTemplate` data (C7).
public enum MotionPreset {
    public struct Preset: Sendable, Identifiable {
        public let id: String
        public let title: String
        /// Whether it suits text items (true) or pictures (false).
        public let forText: Bool
        public let template: MotionTemplate
    }

    // Ken Burns: 12% over the length, panning across the margin that zoom leaves; text moves take 0.3 s.
    private static let data = #"""
        [
          {"id": "zoom-in", "title": "Slow zoom in", "keys": {"zoom": [{"t": 0, "value": 1, "ease": "linear"}, {"t": 1, "value": 1.12}]}},
          {"id": "zoom-out", "title": "Slow zoom out", "keys": {"zoom": [{"t": 0, "value": 1.12, "ease": "linear"}, {"t": 1, "value": 1}]}},
          {"id": "pan-left", "title": "Pan left", "keys": {"zoom": [{"t": 0, "value": 1.12}],
            "pan": [{"t": 0, "value": {"width": 0.05}, "ease": "linear"}, {"t": 1, "value": {"width": -0.05}}]}},
          {"id": "pan-right", "title": "Pan right", "keys": {"zoom": [{"t": 0, "value": 1.12}],
            "pan": [{"t": 0, "value": {"width": -0.05}, "ease": "linear"}, {"t": 1, "value": {"width": 0.05}}]}},
          {"id": "pan-up", "title": "Pan up", "keys": {"zoom": [{"t": 0, "value": 1.12}],
            "tilt": [{"t": 0, "value": {"height": -0.05}, "ease": "linear"}, {"t": 1, "value": {"height": 0.05}}]}},
          {"id": "pan-down", "title": "Pan down", "keys": {"zoom": [{"t": 0, "value": 1.12}],
            "tilt": [{"t": 0, "value": {"height": 0.05}, "ease": "linear"}, {"t": 1, "value": {"height": -0.05}}]}},
          {"id": "fade-in-out", "title": "Fade in and out", "text": true, "keys": {"opacity": [
            {"t": 0, "value": 0, "ease": "out"}, {"s": 0.3, "value": 1, "ease": "linear"},
            {"s": -0.3, "value": 1, "ease": "in"}, {"t": 1, "value": 0}]}},
          {"id": "pop-in", "title": "Pop in", "text": true, "keys": {
            "zoom": [{"t": 0, "value": 0.6, "ease": "out"}, {"s": 0.3, "value": 1.08}, {"s": 0.45, "value": 1}],
            "opacity": [{"t": 0, "value": 0, "ease": "out"}, {"s": 0.15, "value": 1}]}},
          {"id": "slide-up", "title": "Slide up", "text": true, "keys": {
            "tilt": [{"t": 0, "value": {"height": -0.04}, "ease": "out"}, {"s": 0.3, "value": 0}],
            "opacity": [{"t": 0, "value": 0, "ease": "out"}, {"s": 0.3, "value": 1}]}},
          {"id": "zoom-punch", "title": "Zoom punch", "text": true, "keys": {
            "zoom": [{"t": 0, "value": 1.25, "ease": "out"}, {"s": 0.3, "value": 1}]}}
        ]
        """#

    public static let all: [Preset] = {
        // The data above is fixed; a mistake in it is a programming error the preset tests catch.
        // swiftlint:disable:next force_try
        let rows = try! JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)).array
        return rows.compactMap { row in
            let fields = row.object
            guard let id = fields["id"]?.string, let keys = fields["keys"],
                let template = try? MotionTemplate(json: keys, label: id)
            else { return nil }
            return Preset(id: id, title: fields["title"]?.string ?? id, forText: fields["text"]?.bool ?? false,
                          template: template)
        }
    }()

    /// Keys for `id` on an item of `duration` frames in a `width`×`height` frame, at `fps`.
    public static func motion(_ id: String, duration: Int, width: Int, height: Int, fps: FrameRate) throws -> ItemMotion {
        guard let preset = all.first(where: { $0.id == id }) else {
            throw ProjectError.invalid(
                "Unknown motion preset \(id); use \(all.map(\.id).joined(separator: ", ")) or none")
        }
        return try preset.template.motion(duration: duration, width: width, height: height, fps: fps)
    }
}

/// Zoom, pan and tilt that frame one rectangle of a clip's picture (`clip motion --focus`): the rectangle, in the
/// source picture's pixels as seen (origin top left), is scaled to fit the visible band of the frame (the whole frame
/// by default; the part a camera overlay leaves in a split layout) and centred in it, and the pan and tilt are kept
/// so that no edge of the picture comes inside the band where the picture covers it.
public enum MotionFocus {
    public struct Framing: Sendable, Equatable {
        public let zoom: Double
        public let pan: Double
        public let tilt: Double
    }

    /// `x,y,w,h` in source pixels.
    public static func parse(_ text: String) throws -> Region {
        let numbers = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
            [x, y, w, h].allSatisfy(\.isFinite), w >= 1, h >= 1
        else { throw ProjectError.invalid("focus must be x,y,width,height in source pixels") }
        return Region(x: x, y: y, width: w, height: h)
    }

    public struct Region: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The framing of `rect` for a `source`-sized picture on a `canvas`-sized frame, fitted or filled like the clip
    /// (`fill`), inside `band` (canvas pixels from the top left; the whole canvas when nil).
    public static func framing(
        _ rect: Region, source: (width: Double, height: Double), canvas: (width: Double, height: Double), fill: Bool,
        within band: Region? = nil
    ) throws -> Framing {
        let sourceWidth = source.width, sourceHeight = source.height
        let canvasWidth = canvas.width, canvasHeight = canvas.height
        guard sourceWidth > 0, sourceHeight > 0, canvasWidth > 0, canvasHeight > 0 else {
            throw ProjectError.invalid("The clip's picture size is unknown")
        }
        let left = max(0, rect.x), top = max(0, rect.y)
        let right = min(sourceWidth, rect.x + rect.width), bottom = min(sourceHeight, rect.y + rect.height)
        guard right - left >= 1, bottom - top >= 1 else { throw ProjectError.invalid("focus lies outside the picture") }
        let bandLeft = max(0, band?.x ?? 0), bandTop = max(0, band?.y ?? 0)
        let bandRight = min(canvasWidth, band.map { $0.x + $0.width } ?? canvasWidth)
        let bandBottom = min(canvasHeight, band.map { $0.y + $0.height } ?? canvasHeight)
        guard bandRight - bandLeft >= 1, bandBottom - bandTop >= 1 else {
            throw ProjectError.invalid("within lies outside the frame")
        }
        let horizontal = canvasWidth / sourceWidth, vertical = canvasHeight / sourceHeight
        let base = fill ? max(horizontal, vertical) : min(horizontal, vertical)
        let zoomRange = ItemMotion.ranges["zoom"] ?? 0.01...100
        let zoom = min(zoomRange.upperBound, max(zoomRange.lowerBound,
            min((bandRight - bandLeft) / ((right - left) * base), (bandBottom - bandTop) / ((bottom - top) * base))))
        let scale = base * zoom
        // Centre of the rectangle to the centre of the band (tilt is up, source y grows down).
        var pan = (sourceWidth / 2 - (left + right) / 2) * scale + ((bandLeft + bandRight) / 2 - canvasWidth / 2)
        var tilt = ((top + bottom) / 2 - sourceHeight / 2) * scale - ((bandTop + bandBottom) / 2 - canvasHeight / 2)
        // The picture spans its half size either side of the frame's centre moved by pan and tilt; where it is at least
        // as large as the band, no edge of it may come inside the band.
        let halfWidth = sourceWidth * scale / 2, halfHeight = sourceHeight * scale / 2
        if 2 * halfWidth >= bandRight - bandLeft {
            pan = min(bandLeft - canvasWidth / 2 + halfWidth, max(bandRight - canvasWidth / 2 - halfWidth, pan))
        }
        if 2 * halfHeight >= bandBottom - bandTop {
            tilt = min(canvasHeight / 2 + halfHeight - bandBottom, max(canvasHeight / 2 - halfHeight - bandTop, tilt))
        }
        func rounded(_ value: Double, _ places: Double) -> Double { (value * places).rounded() / places }
        return Framing(zoom: rounded(zoom, 1000), pan: rounded(pan, 10), tilt: rounded(tilt, 10))
    }
}
