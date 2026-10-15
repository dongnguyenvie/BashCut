import Foundation

/// A transition as data (flexibility audit C5): per side, the outgoing and the incoming picture, each property runs
/// through its values over the tween (two values: from → to; more: evenly spaced points, straight between them), after
/// the transition's easing. The built-in kinds are rows of this table; a transition's `motion` field makes any kind.
///
/// Properties: `zoom` (scale around the frame centre, 1 = unchanged), `panX` and `panY` (offset as a share of the
/// frame width and height; right and up), `rotation` (degrees, counterclockwise), `opacity` (0–1), `exposure` (EV),
/// `scaleX` (horizontal squeeze around the centre, 1 = unchanged), `reveal` (share of the width shown, from the
/// left; a wipe), `swing` (degrees turned about the left edge in perspective, positive = the right edge goes away),
/// `rgbSplit` (red and blue shifted apart by this share of the width; a glitch), `halftone` (dot spacing as a share
/// of the width; 0 = off), `blur` (soft blur radius as a share of the width), `blurX` and `blurY` (motion blur along
/// that axis, as a share of the width), `revealFromRight`, `revealFromTop` and `revealFromBottom` (wipes from those
/// edges), `revealCenter` (share of the width shown around the centre; a split), `iris` (a circle from the centre,
/// 1 = the whole frame), `diamond` (the same as a diamond), `zoomBlur` (a blur streaked out from the centre, as a share
/// of the width), `hue` (degrees turned around the colour wheel), `saturation` (1 = unchanged) and `kaleidoscope`
/// (0 = off, 1 = a full six-way mirror turned once). A property a side does not list stays unchanged.
public struct TransitionMotion: Sendable, Equatable {
    public var outgoing: [String: [Double]]
    public var incoming: [String: [Double]]

    public static let ranges: [String: ClosedRange<Double>] = [
        "zoom": 0.01...100, "panX": -10...10, "panY": -10...10, "rotation": -3600...3600, "opacity": 0...1,
        "exposure": -10...10, "scaleX": 0...100, "reveal": 0...1, "swing": -89...89, "rgbSplit": 0...0.2,
        "halftone": 0...0.1, "blur": 0...0.1, "blurX": 0...0.2, "blurY": 0...0.2, "revealFromRight": 0...1,
        "revealFromTop": 0...1, "revealFromBottom": 0...1, "revealCenter": 0...1, "iris": 0...1, "diamond": 0...1,
        "zoomBlur": 0...0.2, "hue": -360...360, "saturation": 0...4, "kaleidoscope": 0...1,
    ]

    public init(outgoing: [String: [Double]] = [:], incoming: [String: [Double]] = [:]) {
        self.outgoing = outgoing
        self.incoming = incoming
    }

    /// The built-in kinds in groups for the Transitions panel; the groups follow the technique names of
    /// eyecannndy.com/technique/transition (whip, wipe, shape, crash, roll, arc, infinite, screen, seamless); fade and
    /// stylized hold its most used cut techniques (flash cut, light flash, double exposure, colour shift, kaleidoscope).
    public static let groups: [(name: String, kinds: [String])] = [
        ("Fade", ["dissolve", "blink", "flash", "dip-black", "double-exposure"]),
        ("Whip", ["whip", "whip-right", "whip-up", "whip-down"]),
        ("Wipe", ["wipe", "wipe-right", "wipe-up", "wipe-down", "barn-door", "shutter", "slide", "slide-up"]),
        ("Shape", ["iris", "diamond"]),
        ("Crash", ["zoom", "crash-zoom", "crash-out"]),
        ("Roll", ["spin", "roll", "roll-right"]),
        ("Arc", ["swing", "arc", "arc-right"]),
        ("Infinite", ["infinite-zoom", "infinite-out"]),
        ("Screen", ["screen-in", "screen-out"]),
        ("Seamless", ["blur", "seamless-zoom"]),
        ("Stylized", ["glitch", "halftone", "flicker", "color-shift", "kaleidoscope"]),
    ]

    /// Values that jump to the next picture between a quarter and half of the tween (a cut that lands mid-way).
    private static let midCut: [Double] = [0, 0, 1, 1, 1]

    /// The built-in kinds, as data.
    public static let builtIns: [String: TransitionMotion] = [
        "dissolve": TransitionMotion(incoming: ["opacity": [0, 1]]),
        // A whip pan: both pictures slide out of the frame together, smeared along the move at its fastest.
        "whip": TransitionMotion(
            outgoing: ["panX": [0, -1], "blurX": [0, 0.06, 0.12]], incoming: ["panX": [1, 0], "blurX": [0.12, 0.06, 0]]),
        "whip-right": TransitionMotion(
            outgoing: ["panX": [0, 1], "blurX": [0, 0.06, 0.12]], incoming: ["panX": [-1, 0], "blurX": [0.12, 0.06, 0]]),
        "whip-up": TransitionMotion(
            outgoing: ["panY": [0, 1], "blurY": [0, 0.06, 0.12]], incoming: ["panY": [-1, 0], "blurY": [0.12, 0.06, 0]]),
        "whip-down": TransitionMotion(
            outgoing: ["panY": [0, -1], "blurY": [0, 0.06, 0.12]], incoming: ["panY": [1, 0], "blurY": [0.12, 0.06, 0]]),
        // Exposure peaks mid-way (4 EV), along a sine.
        "blink": TransitionMotion(
            outgoing: ["exposure": [0, 2.828, 4, 2.828, 0]],
            incoming: ["exposure": [0, 2.828, 4, 2.828, 0], "opacity": [0, 1]]),
        "zoom": TransitionMotion(outgoing: ["zoom": [1, 0.9]], incoming: ["zoom": [1.25, 1], "opacity": [0, 1]]),
        "spin": TransitionMotion(outgoing: ["rotation": [0, -90]], incoming: ["rotation": [90, 0], "opacity": [0, 1]]),
        "shutter": TransitionMotion(outgoing: ["scaleX": [1, 0]], incoming: ["scaleX": [0, 1]]),
        "wipe": TransitionMotion(incoming: ["reveal": [0, 1]]),
        "wipe-right": TransitionMotion(incoming: ["revealFromRight": [0, 1]]),
        "wipe-up": TransitionMotion(incoming: ["revealFromBottom": [0, 1]]),
        "wipe-down": TransitionMotion(incoming: ["revealFromTop": [0, 1]]),
        // Barn doors: the next picture opens from a line down the middle.
        "barn-door": TransitionMotion(incoming: ["revealCenter": [0, 1]]),
        // Shapes: the next picture grows from the centre inside a circle or a diamond.
        "iris": TransitionMotion(incoming: ["iris": [0, 1]]),
        "diamond": TransitionMotion(incoming: ["diamond": [0, 1]]),
        // A crash zoom: the camera slams in with a flash and a blur, and the next picture lands already pulled in.
        "crash-zoom": TransitionMotion(
            outgoing: ["zoom": [1, 1.2, 2.4], "zoomBlur": [0, 0.04, 0.1], "exposure": [0, 0.5, 2]],
            incoming: ["zoom": [1.6, 1.1, 1], "zoomBlur": [0.1, 0.04, 0], "exposure": [2, 0.5, 0], "opacity": midCut]),
        // The reverse: the camera snaps back out of the last picture and out of a close one into the next.
        "crash-out": TransitionMotion(
            outgoing: ["zoom": [1, 0.85, 0.45], "zoomBlur": [0, 0.04, 0.1], "exposure": [0, 0.5, 2]],
            incoming: ["zoom": [2, 1.2, 1], "zoomBlur": [0.1, 0.04, 0], "exposure": [2, 0.5, 0], "opacity": midCut]),
        // A camera roll: the frame turns a quarter each side of the cut, pushed in so no corner shows, blurred as it turns.
        "roll": TransitionMotion(
            outgoing: ["rotation": [0, 90], "zoom": [1, 2.2], "blur": [0, 0.025]],
            incoming: ["rotation": [-90, 0], "zoom": [2.2, 1], "blur": [0.025, 0], "opacity": midCut]),
        "roll-right": TransitionMotion(
            outgoing: ["rotation": [0, -90], "zoom": [1, 2.2], "blur": [0, 0.025]],
            incoming: ["rotation": [90, 0], "zoom": [2.2, 1], "blur": [0.025, 0], "opacity": midCut]),
        // An arc: the camera orbits sideways, so the picture slides and tilts a little, pushed in to keep the edges.
        "arc": TransitionMotion(
            outgoing: ["panX": [0, -0.25], "zoom": [1, 1.5], "rotation": [0, 4], "blurX": [0, 0.1]],
            incoming: ["panX": [0.25, 0], "zoom": [1.5, 1], "rotation": [-4, 0], "blurX": [0.1, 0], "opacity": midCut]),
        "arc-right": TransitionMotion(
            outgoing: ["panX": [0, 0.25], "zoom": [1, 1.5], "rotation": [0, -4], "blurX": [0, 0.1]],
            incoming: ["panX": [-0.25, 0], "zoom": [1.5, 1], "rotation": [4, 0], "blurX": [0.1, 0], "opacity": midCut]),
        // An endless zoom: the next picture waits small in the middle of the last one and the camera dives into it.
        "infinite-zoom": TransitionMotion(
            outgoing: ["zoom": [1, 3.3], "zoomBlur": [0, 0.08]],
            incoming: ["zoom": [0.3, 1], "zoomBlur": [0.04, 0], "opacity": [0, 1, 1]]),
        // The other way: the last picture falls away into the middle of the next one.
        "infinite-out": TransitionMotion(
            outgoing: ["zoom": [1, 0.3]],
            incoming: ["zoom": [3.3, 1], "zoomBlur": [0.08, 0], "opacity": [0, 1]]),
        // Into a screen: the last picture darkens as the camera pushes on, the next one is a card that fills the frame.
        "screen-in": TransitionMotion(
            outgoing: ["zoom": [1, 2.5], "exposure": [0, -1.5]],
            incoming: ["zoom": [0.45, 0.5, 1], "opacity": [0, 1, 1]]),
        // Out of a screen: the last picture shrinks into a card on black, then the next one comes up.
        "screen-out": TransitionMotion(
            outgoing: ["zoom": [1, 0.5, 0.45], "exposure": [0, -0.5]],
            incoming: ["zoom": [1.15, 1], "opacity": [0, 0, 1]]),
        // Seamless: the pictures melt into each other through a blur, still or moving on with the camera.
        "blur": TransitionMotion(
            outgoing: ["blur": [0, 0.03]], incoming: ["blur": [0.03, 0], "opacity": [0, 1]]),
        "seamless-zoom": TransitionMotion(
            outgoing: ["zoom": [1, 1.3], "zoomBlur": [0, 0.05]],
            incoming: ["zoom": [0.8, 1], "zoomBlur": [0.05, 0], "opacity": [0, 1]]),
        // A flash cut: the picture burns out to white and the next one comes back out of it.
        "flash": TransitionMotion(
            outgoing: ["exposure": [0, 6, 6]], incoming: ["exposure": [6, 6, 0], "opacity": [0, 0, 1, 1]]),
        // Down to black and up again.
        "dip-black": TransitionMotion(
            outgoing: ["exposure": [0, -10]], incoming: ["exposure": [-10, 0], "opacity": [0, 0, 1, 1]]),
        // Both pictures hold over each other for a while, the next one drifting in, before the last one goes.
        "double-exposure": TransitionMotion(
            outgoing: ["zoom": [1, 1.06]], incoming: ["zoom": [1.08, 1], "opacity": [0, 0.5, 0.5, 0.5, 1]]),
        // A strobe between the two pictures that settles on the next one.
        "flicker": TransitionMotion(incoming: ["opacity": [0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1]]),
        // The colours run round the wheel and come back on the next picture.
        "color-shift": TransitionMotion(
            outgoing: ["hue": [0, 180], "saturation": [1, 2.2]],
            incoming: ["hue": [-180, 0], "saturation": [2.2, 1], "opacity": midCut]),
        // The picture folds into a turning kaleidoscope and the next one unfolds out of it.
        "kaleidoscope": TransitionMotion(
            outgoing: ["kaleidoscope": [0, 1]], incoming: ["kaleidoscope": [1, 0], "opacity": midCut]),
        // The next picture slides in over the last one, which stays put.
        "slide": TransitionMotion(incoming: ["panX": [1, 0], "blurX": [0.04, 0]]),
        "slide-up": TransitionMotion(incoming: ["panY": [-1, 0], "blurY": [0.04, 0]]),
        // The next card swings in about its left edge while the last one falls back (explainer card swap).
        "swing": TransitionMotion(
            outgoing: ["zoom": [1, 0.92], "exposure": [0, -1]],
            incoming: ["swing": [70, 0], "opacity": [0, 1, 1]]),
        // Red and blue tear apart in uneven jumps, the picture jitters, and the cut lands mid-way.
        "glitch": TransitionMotion(
            outgoing: ["rgbSplit": [0, 0.02, 0.006, 0.05, 0.03], "panX": [0, 0.015, -0.02, 0.01, 0.03]],
            incoming: ["rgbSplit": [0.04, 0.012, 0.05, 0.015, 0], "panX": [-0.03, 0.02, -0.01, 0.008, 0],
                       "opacity": [0, 0, 1, 1, 1]]),
        // The picture breaks into print dots that grow, then the next resolves out of dots.
        "halftone": TransitionMotion(
            outgoing: ["halftone": [0.004, 0.035]],
            incoming: ["halftone": [0.035, 0.004], "opacity": [0, 1]]),
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
