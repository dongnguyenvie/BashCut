import Foundation

/// Transitions in the list (#623): a cut transition into a clip or graphic (`transition`), and a title's or graphic's
/// own In and Out (`enter`, `exit`, the item fields). Each is `"kind"`, `"kind:frames"`, `{kind, duration (frames),
/// easing, motion}` or `"none"` (removes one set on the timeline). An apply keeps the cut transitions and In/Out set
/// on built items by hand (`clip transition`, the inspector) when the item is built again and the list sets none.
extension PlanCut {
    /// A transition the list gives: `kind` nil is `none`; `duration` nil takes a default.
    public struct Edge: Sendable, Equatable {
        public var kind: String?
        public var duration: Int?
        public var easing: String?
        public var motion: JSONValue?
    }

    /// The prefix of the IDs of cut transitions the list set, so a later apply tells them from hand-set ones.
    static let transitionPrefix = "plan-tx-"

    /// `"kind"`, `"kind:frames"`, `"none"` or `{kind, duration, easing, motion}`; nil when absent. The kind must be a
    /// built-in one (`TimelineTransition.renderedKinds`) or come with a motion.
    static func decodeEdge(_ value: JSONValue?, entry: String, field: String) throws -> Edge? {
        guard let value, value != .null else { return nil }
        let path = "\(entry).\(field)"
        let edge: Edge
        switch value {
        case .string("none"):
            return Edge()
        case .string(let text):
            edge = try parseEdge(text, path: path)
        case .object(let fields):
            guard let kind = fields["kind"]?.string else { throw ProjectError.invalid("\(path).kind: required") }
            if let duration = fields["duration"], duration.int == nil {
                throw ProjectError.invalid("\(path).duration: a whole number of frames")
            }
            if let easing = fields["easing"], easing.string == nil { throw ProjectError.invalid("\(path).easing: a string") }
            edge = Edge(kind: kind, duration: fields["duration"]?.int, easing: fields["easing"]?.string, motion: fields["motion"])
        default:
            throw ProjectError.invalid("\(path): \"kind\", \"kind:frames\", \"none\" or {kind, duration, easing}")
        }
        if let duration = edge.duration, !(1...ItemTransition.maximumDuration).contains(duration) {
            throw ProjectError.invalid("\(path).duration: 1–\(ItemTransition.maximumDuration) frames")
        }
        var check = TimelineTransition(id: "check", kind: edge.kind ?? "", from: "a", to: "b", duration: 1, easing: edge.easing)
        check.fields["motion"] = edge.motion
        do { try check.checkKindAndEasing() } catch let ProjectError.invalid(message) {
            throw ProjectError.invalid("\(path): \(message)")
        }
        return edge
    }

    /// `"kind"` or `"kind:frames"`.
    static func parseEdge(_ text: String, path: String) throws -> Edge {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), !parts[0].isEmpty else {
            throw ProjectError.invalid("\(path): \"kind\" or \"kind:frames\", such as \"dissolve:12\"")
        }
        guard parts.count == 2 else { return Edge(kind: parts[0]) }
        guard let frames = Int(parts[1]) else { throw ProjectError.invalid("\(path): frames after : must be a whole number") }
        return Edge(kind: parts[0], duration: frames)
    }

    /// What was set by hand on the items an apply built, before the apply removes them: cut transitions into or out
    /// of them, and their `enter`/`exit` (the list's own carry `planCut`).
    struct HandSet {
        var transitions: [TimelineTransition] = []
        var edges: [String: [String: JSONValue]] = [:]
        /// Speed and the music bed's span set by hand.
        var hand: HandEdits

        init(_ project: Project) {
            let built = project.tracks.flatMap(\.items).filter { $0.fields[tag] != nil }
            hand = HandEdits(built)
            let ids = Set(built.map(\.id))
            transitions = project.transitions.filter {
                (ids.contains($0.toItemID) || ids.contains($0.fromItemID)) && !$0.id.hasPrefix(transitionPrefix)
            }
            for item in built {
                for field in ItemTransition.fields {
                    guard let value = item[field], value != .null, value.object[tag] == nil else { continue }
                    edges[item.id, default: [:]][field] = value
                }
            }
        }
    }

    /// The list's transitions and In/Out as (entry, its first picture item ID, field, edge); `transition` is the cut.
    static func listedEdges(_ spec: Spec) -> [(entry: String, field: String, edge: Edge)] {
        spec.clips.compactMap { clip in clip.transition.map { (clip.id, "transition", $0) } }
            + spec.graphics.flatMap { graphic in
                [("transition", graphic.transition), ("enter", graphic.enter), ("exit", graphic.exit)]
                    .compactMap { field, edge in edge.map { (graphic.id, field, $0) } }
            }
            + spec.titles.flatMap { title in
                [("enter", title.enter), ("exit", title.exit)].compactMap { field, edge in edge.map { (title.id, field, $0) } }
            }
    }

    /// The first video or text item built for `entry` (a clip's picture or first cover, a graphic, a title).
    static func firstPicture(of entry: String, in project: Project) -> (item: Item, track: Track)? {
        project.tracks.filter { $0.kind == TrackKind.video || $0.kind == TrackKind.text }
            .flatMap { track in track.items.map { ($0, track) } }
            .filter { $0.0.fields[tag] == .string(entry) }
            .min { ($0.0.at, $0.0.id) < ($1.0.at, $1.0.id) }
    }

    /// The item on `track` that ends where `item` starts: the other side of a cut into it.
    static func before(_ item: Item, on track: Track) -> Item? {
        guard track.kind == TrackKind.video else { return nil }
        return track.items.filter { $0.id != item.id && $0.end == item.at }.max { $0.id < $1.id }
    }

    /// Sets what was set by hand back on the rebuilt items, then the list's own transitions and In/Out over it.
    static func applyEdges(_ spec: Spec, kept: HandSet, in planner: inout LayerPlanner) throws {
        let listed = listedEdges(spec)
        try restore(kept, except: listed, in: &planner)
        for (entry, field, edge) in listed {
            guard let (item, track) = firstPicture(of: entry, in: planner.project) else { continue }
            if field == "transition" {
                try setCut(edge, into: item, on: track, entry: entry, in: &planner)
            } else {
                var value: JSONValue = .null
                if let kind = edge.kind {
                    let fps = planner.project.fps.value
                    let duration = edge.duration ?? max(1, min(Int((fps / 2).rounded()), item.duration / 3))
                    var fields = ItemTransition(
                        kind: kind, duration: duration, easing: edge.easing ?? TimelineTransition.defaultEasing,
                        motion: edge.motion).json.object
                    fields[tag] = .string(entry)
                    value = .object(fields)
                }
                try planner.add([.setProperties(item: item.id, patch: [field: value])])
            }
        }
    }

    /// The hand-set cut transitions (re-joined to the picture now before their item) and In/Out the list does not set.
    static func restore(
        _ kept: HandSet, except listed: [(entry: String, field: String, edge: Edge)], in planner: inout LayerPlanner
    ) throws {
        let listedCuts = Set(listed.filter { $0.field == "transition" }.compactMap {
            firstPicture(of: $0.entry, in: planner.project)?.item.id
        })
        for old in kept.transitions where !listedCuts.contains(old.toItemID) {
            let tracks = planner.project.tracks
            guard let track = tracks.first(where: { $0.items.contains { $0.id == old.toItemID } }),
                let item = track.items.first(where: { $0.id == old.toItemID }), let from = before(item, on: track)
            else { continue }
            var candidate = old
            candidate.fields["from"] = .string(from.id)
            guard planner.project.transitionIsValid(candidate) else { continue }
            try planner.add([.upsertTransition(
                id: old.id, kind: old.kind, from: from.id, to: old.toItemID, duration: old.duration,
                easing: old.fields["easing"]?.string, motion: old.fields["motion"])])
        }
        let items = Dictionary(planner.project.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, fields) in kept.edges.sorted(by: { $0.key < $1.key }) {
            guard let item = items[id], let entry = item.fields[tag]?.string else { continue }
            let patch = fields.filter { field, _ in !listed.contains { $0.entry == entry && $0.field == field } }
            if !patch.isEmpty { try planner.add([.setProperties(item: id, patch: patch)]) }
        }
    }

    /// The list's cut transition into `item` (none: removes the one there); left out when nothing ends where it
    /// starts or it is longer than the cut allows (`transitionProblems` says so).
    static func setCut(_ edge: Edge, into item: Item, on track: Track, entry: String, in planner: inout LayerPlanner) throws {
        guard let kind = edge.kind else {
            if let into = planner.project.transitions.first(where: { $0.toItemID == item.id }) {
                try planner.add([.deleteTransition(id: into.id)])
            }
            return
        }
        guard let from = before(item, on: track) else { return }
        let fps = planner.project.fps.value
        let duration = edge.duration ?? max(1, min(Int((fps / 2).rounded()), from.duration, item.duration))
        guard duration <= min(from.duration, item.duration) else { return }
        try planner.add([.upsertTransition(
            id: transitionPrefix + entry, kind: kind, from: from.id, to: item.id, duration: duration,
            easing: edge.easing, motion: edge.motion)])
    }

    /// A cut transition the list gives that the build could not set: the entry's first picture has no clip ending
    /// where it starts on its layer, or the transition is longer than the shorter side of the cut.
    public static func transitionProblems(_ spec: Spec, on after: Project) -> [Problem] {
        listedEdges(spec).compactMap { entry, field, edge -> Problem? in
            guard field == "transition", edge.kind != nil,
                !after.transitions.contains(where: { $0.id == transitionPrefix + entry }),
                let (item, track) = firstPicture(of: entry, in: after)
            else { return nil }
            guard let from = before(item, on: track) else {
                return Problem(
                    id: "transition-no-cut", severity: "error", entry: entry,
                    detail: "transition plays on a cut, and nothing ends where \(entry) starts on its layer (the first "
                        + "clip, or a gap): remove it, or give enter for an entrance of its own")
            }
            let longest = min(from.duration, item.duration)
            return Problem(
                id: "transition-too-long", severity: "error", entry: entry,
                detail: "transition \(edge.duration ?? 0) frames is longer than the shorter side of the cut (\(longest) "
                    + "frames): give at most \(longest)", facts: ["maxFrames": .integer(longest)])
        }
    }
}
