import Foundation

/// An item's own entrance or exit (`enter`, `exit`): a transition kind played on the item alone, inside its own frame
/// (a text box, a placed picture), for an item that is not part of a video cut: text and captions, stickers, graphics
/// and overlay clips. `{kind, duration, easing?, motion?}` as on a transition; other fields are kept.
///
/// `enter` plays the kind's incoming side over the item's first `duration` frames, `exit` its outgoing side over the
/// last ones. A kind whose outgoing side leaves the picture as it is (a wipe, an iris: the next picture covers it)
/// exits by running its incoming side backwards, so the item wipes or closes away. A side that does not hide the
/// item by itself (a whip, a zoom) fades it in or out on the way.
public struct ItemTransition: Sendable, Equatable {
    public static let fields = ["enter", "exit"]
    /// The longest entrance or exit, in frames.
    public static let maximumDuration = 100_000
    /// Properties that hide the picture at 0: the wipes and shapes, and the horizontal squeeze.
    static let hidingProperties = [
        "reveal", "revealFromRight", "revealFromTop", "revealFromBottom", "revealCenter", "iris", "diamond", "scaleX",
    ]

    public var kind: String
    public var duration: Int
    public var easing: String
    /// The `motion` field, else nil (the built-in row of `kind`).
    public var motion: JSONValue?

    public init(kind: String, duration: Int, easing: String = TimelineTransition.defaultEasing, motion: JSONValue? = nil) {
        self.kind = kind
        self.duration = duration
        self.easing = easing
        self.motion = motion
    }

    /// Reads `value` without checking it; nil when it is not an object with a kind and a duration.
    public init?(json value: JSONValue?) {
        guard case .object(let fields)? = value, let kind = fields["kind"]?.string, let duration = fields["duration"]?.int
        else { return nil }
        self.init(
            kind: kind, duration: duration, easing: fields["easing"]?.string ?? TimelineTransition.defaultEasing,
            motion: fields["motion"])
    }

    /// The fields this value sets; a linear easing and a built-in motion are no field.
    public var json: JSONValue {
        var fields: [String: JSONValue] = ["kind": .string(kind), "duration": .integer(duration)]
        if easing != TimelineTransition.defaultEasing { fields["easing"] = .string(easing) }
        if let motion { fields["motion"] = motion }
        return .object(fields)
    }

    /// Checks `value` as the item field `path` (item.ID.enter): an object with a kind (built in, or any name with a
    /// valid motion), 1…`maximumDuration` frames and a known easing.
    public static func validate(_ value: JSONValue, path: String) throws {
        guard case .object(let fields) = value else { throw ProjectError.invalid("\(path): expected an object") }
        guard fields["kind"]?.string != nil else { throw ProjectError.invalid("\(path).kind: required") }
        guard let duration = fields["duration"]?.int, (1...maximumDuration).contains(duration) else {
            throw ProjectError.invalid("\(path).duration: expected 1–\(maximumDuration) frames")
        }
        if let easing = fields["easing"], easing.string == nil {
            throw ProjectError.invalid("\(path).easing: expected a string")
        }
        var check = TimelineTransition(fields: fields)
        check.fields["id"] = .string("check")
        do { try check.checkKindAndEasing() } catch let ProjectError.invalid(message) {
            throw ProjectError.invalid("\(path): \(message)")
        }
    }

    /// The tracks this entrance (`entering`) or exit plays, as `TransitionMotion.value` reads them: the kind's
    /// incoming side, or its outgoing side (the incoming one backwards when the outgoing leaves the picture as it is),
    /// with a fade when the side does not hide the item at its outer end.
    public func tracks(entering: Bool) -> [String: [Double]] {
        let resolved = TransitionMotion.resolved(kind: kind, motion: motion)
        var side: [String: [Double]]
        if entering {
            side = resolved.incoming
        } else if resolved.outgoing.isEmpty {
            side = resolved.incoming.mapValues { $0.reversed() }
        } else {
            side = resolved.outgoing
        }
        let hidden = { (values: [Double]?) in ((entering ? values?.first : values?.last) ?? 1) <= 0.0001 }
        if side["opacity"] == nil, !Self.hidingProperties.contains(where: { hidden(side[$0]) }) {
            side["opacity"] = entering ? [0, 1] : [1, 0]
        }
        return side
    }
}

extension Item {
    /// The item's entrance (`enter`); nil when it has none.
    public var enterTransition: ItemTransition? { ItemTransition(json: fields["enter"]) }
    /// The item's exit (`exit`); nil when it has none.
    public var exitTransition: ItemTransition? { ItemTransition(json: fields["exit"]) }

    /// `enter` and `exit`, checked; only video and text layers draw them.
    func validateTransitions(on track: Track) throws {
        for name in ItemTransition.fields {
            guard let value = fields[name] else { continue }
            guard track.kind == TrackKind.video || track.kind == TrackKind.text else {
                throw ProjectError.invalid("item.\(id).\(name): only video and text items have an entrance or exit")
            }
            try ItemTransition.validate(value, path: "item.\(id).\(name)")
        }
    }
}

/// An item's entrance and exit at render time: frames from the timeline start, each clamped to the item, and the
/// tracks each plays. Preview and export share it.
public struct ItemAppearance: Sendable, Equatable {
    public struct Side: Sendable, Equatable {
        public let start: Int
        public let duration: Int
        public let easing: String
        public let entering: Bool
        public let motion: TransitionMotion

        /// The side's eased progress at timeline `frame` (fractional), or nil outside it.
        public func progress(at frame: Double) -> Double? {
            guard frame >= Double(start), frame < Double(start + duration) else { return nil }
            return TimelineTransition.eased((frame - Double(start)) / Double(duration), easing: easing)
        }

        /// `property` at timeline `frame`, or nil when the side leaves it unchanged or is not playing.
        public func value(_ property: String, at frame: Double) -> Double? {
            guard let progress = progress(at: frame) else { return nil }
            return motion.value(property, incoming: true, at: progress)
        }
    }

    public let enter: Side?
    public let exit: Side?

    /// `item`'s entrance and exit; an edge that a cut transition already plays (`cutAtStart`, `cutAtEnd`) keeps that
    /// one. Nil when nothing plays.
    public init?(item: Item, cutAtStart: Bool = false, cutAtEnd: Bool = false) {
        func side(_ value: ItemTransition?, entering: Bool) -> Side? {
            guard let value, value.duration > 0, item.duration > 0 else { return nil }
            let duration = min(value.duration, item.duration)
            return Side(
                start: entering ? item.at : item.end - duration, duration: duration, easing: value.easing,
                entering: entering, motion: TransitionMotion(incoming: value.tracks(entering: entering)))
        }
        enter = cutAtStart ? nil : side(item.enterTransition, entering: true)
        exit = cutAtEnd ? nil : side(item.exitTransition, entering: false)
        if enter == nil, exit == nil { return nil }
    }

    /// The side playing at timeline `frame`: the entrance first when both overlap on a short item.
    public func side(at frame: Double) -> Side? {
        if let enter, enter.progress(at: frame) != nil { return enter }
        if let exit, exit.progress(at: frame) != nil { return exit }
        return nil
    }
}

extension ProjectSchema {
    /// `enter` and `exit` of an item.
    static var itemTransitionSchema: JSONValue {
        .object(fields(
            "Video and text items not in a video cut: a transition kind played on the item alone, in its own frame. "
                + "enter plays the incoming side over the first frames; exit the outgoing side (a wipe or shape runs "
                + "backwards) over the last; a side that does not hide the item fades it",
            required: ["kind", "duration"],
            properties: [
                "kind": string(
                    "Transition kind, as on a transition, or any name with motion", pattern: "^[a-z][a-z0-9-]{0,63}$"),
                "duration": integer("Timeline frames (clamped to the item)", minimum: 1, maximum: ItemTransition.maximumDuration),
                "easing": string("How the tween runs: " + TimelineTransition.easingSummary + "; linear when absent"),
                "motion": .object([
                    "type": .string("object"),
                    "description": .string("The tween as data, as on a transition (enter reads incoming, exit outgoing)"),
                ]),
            ]))
    }
}
