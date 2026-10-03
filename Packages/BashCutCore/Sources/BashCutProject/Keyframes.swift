import Foundation

/// Animation of an item's picture over its length: the item field `keyframes`, an object from property name to a
/// list of `{"frame", "value", "ease"?}` sorted by frame. Frames count from the item's start (0 = its first frame)
/// and move with the picture when the item is split or its start is trimmed. Before the first key the property
/// keeps the first value, after the last key the last value. `ease` shapes the change from that key to the next.
///
/// Properties: `zoom` (scale over the fitted or filled size, like `transform.zoom`), `pan` and `tilt` (offset in
/// output pixels, like `transform.pan`/`tilt`; tilt is up), `rotation` (degrees, counterclockwise) and `opacity`.
/// A property with keys replaces the item's static value; the others keep it. On text items, zoom scales the text
/// around its own position.
public struct ItemMotion: Sendable, Equatable {
    public enum Ease: String, Sendable, CaseIterable {
        case linear
        case easeIn = "in"
        case easeOut = "out"
        case easeInOut = "inOut"
        /// Keeps this key's value until the next key.
        case hold

        func apply(_ t: Double) -> Double {
            switch self {
            case .linear: t
            case .easeIn: t * t * t
            case .easeOut: 1 - pow(1 - t, 3)
            case .easeInOut: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            case .hold: 0
            }
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

    public static let ranges: [String: ClosedRange<Double>] = [
        "zoom": 0.01...100, "pan": -65536...65536, "tilt": -65536...65536, "rotation": -3600...3600, "opacity": 0...1,
    ]
    public static let summaries = [
        "zoom": "Scale over the fitted or filled size (1 = unchanged)",
        "pan": "Horizontal offset in output pixels",
        "tilt": "Vertical offset in output pixels, up",
        "rotation": "Rotation in degrees, counterclockwise",
        "opacity": "Opacity, 0 to 1",
    ]

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
                        throw ProjectError.invalid(
                            "keyframes.\(name): ease must be one of \(Ease.allCases.map(\.rawValue).joined(separator: ", "))")
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

    /// The same animation with every key `offset` frames later (negative: earlier).
    public func shifted(by offset: Int) -> ItemMotion {
        ItemMotion(keys: keys.mapValues { $0.map { Key(frame: $0.frame + offset, value: $0.value, ease: $0.ease) } })
    }
}

extension Item {
    /// Fields a `setProperties` patch removes when it sets them to null.
    public static let removableFields: Set<String> = ["freezeFrame", "keyframes", "words", "wordStyle"]

    /// The item's keyframes; nil when it has none (or they are invalid, which validation rejects).
    public var motion: ItemMotion? {
        guard let value = fields["keyframes"], let motion = try? ItemMotion(json: value), !motion.isEmpty else {
            return nil
        }
        return motion
    }

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

/// Ready-made animations for `clip motion` and the Inspector's Animation menu.
public enum MotionPreset {
    public struct Preset: Sendable, Identifiable {
        public let id: String
        public let title: String
        /// Whether it suits text items (true) or pictures (false).
        public let forText: Bool
    }

    public static let all: [Preset] = [
        Preset(id: "zoom-in", title: "Slow zoom in", forText: false),
        Preset(id: "zoom-out", title: "Slow zoom out", forText: false),
        Preset(id: "pan-left", title: "Pan left", forText: false),
        Preset(id: "pan-right", title: "Pan right", forText: false),
        Preset(id: "pan-up", title: "Pan up", forText: false),
        Preset(id: "pan-down", title: "Pan down", forText: false),
        Preset(id: "fade-in-out", title: "Fade in and out", forText: true),
        Preset(id: "pop-in", title: "Pop in", forText: true),
        Preset(id: "slide-up", title: "Slide up", forText: true),
        Preset(id: "zoom-punch", title: "Zoom punch", forText: true),
    ]

    // Keys for `id` on an item of `duration` frames in a `width`×`height` frame, at `fps`. One case per preset keeps
    // each animation next to its name.
    // swiftlint:disable:next cyclomatic_complexity
    public static func motion(_ id: String, duration: Int, width: Int, height: Int, fps: FrameRate) throws -> ItemMotion {
        let end = max(1, duration - 1)
        let quick = max(1, min(end, Int((fps.value * 0.3).rounded())))
        // Ken Burns: 12% over the length, panning across the margin that zoom leaves (6% of the frame per side).
        let zoom = 1.12, panX = Double(width) * 0.05, panY = Double(height) * 0.05
        func keys(_ from: Double, _ to: Double, ease: ItemMotion.Ease = .linear) -> [ItemMotion.Key] {
            [.init(frame: 0, value: from, ease: ease), .init(frame: end, value: to)]
        }
        func still(_ value: Double) -> [ItemMotion.Key] { [.init(frame: 0, value: value)] }
        switch id {
        case "zoom-in": return ItemMotion(keys: ["zoom": keys(1, zoom)])
        case "zoom-out": return ItemMotion(keys: ["zoom": keys(zoom, 1)])
        case "pan-left": return ItemMotion(keys: ["zoom": still(zoom), "pan": keys(panX, -panX)])
        case "pan-right": return ItemMotion(keys: ["zoom": still(zoom), "pan": keys(-panX, panX)])
        case "pan-up": return ItemMotion(keys: ["zoom": still(zoom), "tilt": keys(-panY, panY)])
        case "pan-down": return ItemMotion(keys: ["zoom": still(zoom), "tilt": keys(panY, -panY)])
        case "fade-in-out":
            let fade = min(quick, max(1, duration / 3))
            return ItemMotion(keys: ["opacity": [
                .init(frame: 0, value: 0, ease: .easeOut), .init(frame: fade, value: 1, ease: .linear),
                .init(frame: max(fade + 1, end - fade), value: 1, ease: .easeIn), .init(frame: max(fade + 2, end), value: 0),
            ]])
        case "pop-in":
            let settle = min(end, quick + quick / 2)
            return ItemMotion(keys: [
                "zoom": [.init(frame: 0, value: 0.6, ease: .easeOut), .init(frame: quick, value: 1.08),
                         .init(frame: max(quick + 1, settle), value: 1)],
                "opacity": [.init(frame: 0, value: 0, ease: .easeOut), .init(frame: max(1, quick / 2), value: 1)],
            ])
        case "slide-up":
            return ItemMotion(keys: [
                "tilt": [.init(frame: 0, value: -Double(height) * 0.04, ease: .easeOut), .init(frame: quick, value: 0)],
                "opacity": [.init(frame: 0, value: 0, ease: .easeOut), .init(frame: quick, value: 1)],
            ])
        case "zoom-punch":
            return ItemMotion(keys: ["zoom": [
                .init(frame: 0, value: 1.25, ease: .easeOut), .init(frame: quick, value: 1),
            ]])
        default:
            throw ProjectError.invalid(
                "Unknown motion preset \(id); use \(all.map(\.id).joined(separator: ", ")) or none")
        }
    }
}
