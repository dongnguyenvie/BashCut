import Foundation

/// A transition as data (flexibility audit C5): per side, the outgoing and the incoming picture, each property runs
/// through its values over the tween (two values: from → to; more: evenly spaced points, straight between them), after
/// the transition's easing. The built-in kinds are rows of this table; a transition's `motion` field makes any kind.
///
/// Properties: `zoom` (scale around the frame centre, 1 = unchanged), `panX` and `panY` (offset as a share of the
/// frame width and height; right and up), `rotation` (degrees, counterclockwise), `opacity` (0–1), `exposure` (EV),
/// `scaleX` (horizontal squeeze around the centre, 1 = unchanged) and `reveal` (share of the width shown, from the
/// left; a wipe). A property a side does not list stays unchanged.
public struct TransitionMotion: Sendable, Equatable {
    public var outgoing: [String: [Double]]
    public var incoming: [String: [Double]]

    public static let ranges: [String: ClosedRange<Double>] = [
        "zoom": 0.01...100, "panX": -10...10, "panY": -10...10, "rotation": -3600...3600, "opacity": 0...1,
        "exposure": -10...10, "scaleX": 0...100, "reveal": 0...1,
    ]

    public init(outgoing: [String: [Double]] = [:], incoming: [String: [Double]] = [:]) {
        self.outgoing = outgoing
        self.incoming = incoming
    }

    /// The built-in kinds, as data.
    public static let builtIns: [String: TransitionMotion] = [
        "dissolve": TransitionMotion(incoming: ["opacity": [0, 1]]),
        "whip": TransitionMotion(outgoing: ["panX": [0, -1]], incoming: ["panX": [1, 0]]),
        // Exposure peaks mid-way (4 EV), along a sine.
        "blink": TransitionMotion(
            outgoing: ["exposure": [0, 2.828, 4, 2.828, 0]],
            incoming: ["exposure": [0, 2.828, 4, 2.828, 0], "opacity": [0, 1]]),
        "zoom": TransitionMotion(outgoing: ["zoom": [1, 0.9]], incoming: ["zoom": [1.25, 1], "opacity": [0, 1]]),
        "spin": TransitionMotion(outgoing: ["rotation": [0, -90]], incoming: ["rotation": [90, 0], "opacity": [0, 1]]),
        "shutter": TransitionMotion(outgoing: ["scaleX": [1, 0]], incoming: ["scaleX": [0, 1]]),
        "wipe": TransitionMotion(incoming: ["reveal": [0, 1]]),
    ]

    /// `motion` when given, else the built-in row of `kind`, else a dissolve.
    public static func resolved(kind: String, motion: JSONValue?) -> TransitionMotion {
        if let motion, let parsed = try? TransitionMotion(json: motion) { return parsed }
        return builtIns[kind] ?? builtIns["dissolve"]!
    }

    public init(json: JSONValue) throws {
        guard case .object(let fields) = json else { throw ProjectError.invalid("motion: expected an object") }
        if let unknown = fields.keys.first(where: { $0 != "outgoing" && $0 != "incoming" }) {
            throw ProjectError.invalid("motion.\(unknown): use outgoing and incoming")
        }
        func side(_ name: String) throws -> [String: [Double]] {
            guard let value = fields[name] else { return [:] }
            guard case .object(let properties) = value else { throw ProjectError.invalid("motion.\(name): expected an object") }
            var result: [String: [Double]] = [:]
            for (property, list) in properties {
                guard let range = Self.ranges[property] else {
                    throw ProjectError.invalid(
                        "motion.\(name).\(property): unknown; use \(Self.ranges.keys.sorted().joined(separator: ", "))")
                }
                let values = list.array.compactMap(\.double)
                guard (2...16).contains(values.count), values.count == list.array.count,
                    values.allSatisfy({ $0.isFinite && range.contains($0) })
                else { throw ProjectError.invalid("motion.\(name).\(property): 2–16 numbers in \(range)") }
                result[property] = values
            }
            return result
        }
        outgoing = try side("outgoing")
        incoming = try side("incoming")
    }

    public var json: JSONValue {
        let side = { (values: [String: [Double]]) in JSONValue.object(values.mapValues { .array($0.map(JSONValue.number)) }) }
        var fields: [String: JSONValue] = [:]
        if !outgoing.isEmpty { fields["outgoing"] = side(outgoing) }
        if !incoming.isEmpty { fields["incoming"] = side(incoming) }
        return .object(fields)
    }

    /// `property` of one side at eased `progress` (0…1); nil when that side leaves it unchanged.
    public func value(_ property: String, incoming isIncoming: Bool, at progress: Double) -> Double? {
        guard let values = (isIncoming ? incoming : outgoing)[property], let first = values.first, let last = values.last
        else { return nil }
        let position = min(1, max(0, progress)) * Double(values.count - 1)
        let index = Int(position.rounded(.down))
        guard index < values.count - 1 else { return last }
        guard index >= 0 else { return first }
        return values[index] + (values[index + 1] - values[index]) * (position - Double(index))
    }
}
