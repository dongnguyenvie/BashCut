import Foundation

/// A transition between two adjacent clips on a video layer: its kind, length, easing and motion (C5, C6).
public struct TimelineTransition: JSONObject, Identifiable {
    /// The built-in kinds (`TransitionMotion.builtIns`); any other kind needs a `motion` field.
    public static let renderedKinds = ["dissolve", "whip", "blink", "zoom", "spin", "shutter", "wipe"]
    public static let easingSummary = easings.joined(separator: ", ") + " or cubic-bezier(x1,y1,x2,y2)"
    /// How the tween runs over the transition (#77): `linear` (the default, stored as no field), the keyframe
    /// curves `in`, `out` and `inOut`, or any `cubic-bezier(…)` (one ease type with keyframes, flexibility audit C6).
    public static let easings = ["linear", "in", "out", "inOut"]
    public static let defaultEasing = "linear"

    /// Whether `easing` is a tween curve: any keyframe ease but hold.
    public static func isEasing(_ easing: String) -> Bool {
        guard let ease = ItemMotion.Ease(rawValue: easing) else { return false }
        return ease != .hold
    }
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(
        id: String = UUID().uuidString, kind: String, from: String, to: String, duration: Int, easing: String? = nil
    ) {
        fields = [
            "id": .string(id), "kind": .string(kind), "from": .string(from),
            "to": .string(to), "duration": .integer(duration),
        ]
        if let easing, easing != Self.defaultEasing { fields["easing"] = .string(easing) }
    }
    public var id: String { fields["id"]?.string ?? "" }
    public var kind: String { fields["kind"]?.string ?? "" }
    public var fromItemID: String { fields["from"]?.string ?? "" }
    public var toItemID: String { fields["to"]?.string ?? "" }
    public var duration: Int { fields["duration"]?.int ?? 0 }
    public var easing: String { fields["easing"]?.string ?? Self.defaultEasing }
    /// The tween as data: the `motion` field, else the built-in row of the kind.
    public var motion: TransitionMotion { TransitionMotion.resolved(kind: kind, motion: fields["motion"]) }

    /// A kind of 1–64 lowercase letters, digits and dashes that is built in or has a valid `motion`; a known easing.
    public func checkKindAndEasing() throws {
        guard kind.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            throw ProjectError.invalid("Transition kind must be 1–64 lowercase letters, digits or dashes")
        }
        if let motion = fields["motion"] {
            _ = try TransitionMotion(json: motion)
        } else if !Self.renderedKinds.contains(kind) {
            throw ProjectError.invalid(
                "Transition kind \(kind) is not built in (\(Self.renderedKinds.joined(separator: ", "))): give its motion")
        }
        guard Self.isEasing(easing) else { throw ProjectError.invalid("Transition easing must be one of \(Self.easingSummary)") }
    }

    /// `linear` (0...1, clamped) shaped by `easing`; an unknown easing stays linear. Preview and export share it.
    public static func eased(_ linear: Double, easing: String) -> Double {
        let t = min(1, max(0, linear))
        guard easing != defaultEasing, isEasing(easing), let ease = ItemMotion.Ease(rawValue: easing) else { return t }
        return ease.apply(t)
    }
}
