import Foundation

/// Framing a clip's, cover's or overlay's picture by rectangles of its source (plan.cut `focus`, `focusTo`,
/// `focusKeys`, `within`, `ease`), resolved on apply with `MotionFocus` into zoom, pan and tilt keys, like
/// `clip motion --focus`, so the list never carries hand-computed framing.
extension PlanCut {
    /// A panel shown from a source time on: the shot frames `rect` from `at` (source seconds), moving there over
    /// `move` seconds (default `Focus.moveSeconds`) and holding it until the next key.
    public struct FocusKey: Sendable {
        public var at: Double
        public var rect: MotionFocus.Region
        public var move: Double?
    }

    public struct Focus: Sendable {
        /// Framed from the shot's first frame.
        public var rect: MotionFocus.Region?
        /// Moved to by the shot's last frame.
        public var to: MotionFocus.Region?
        public var keys: [FocusKey] = []
        public var within: MotionFocus.Within = .auto
        public var ease: ItemMotion.Ease = .easeInOut

        public static let moveSeconds = 0.5
    }

    /// The fields of a focus on a clip, cover or overlay row.
    static let focusFields: Set<String> = ["focus", "focusTo", "focusKeys", "within", "ease"]

    /// `[x, y, w, h]` or `"x,y,w,h"` in source pixels.
    static func decodeRect(_ value: JSONValue, entry: String, field: String) throws -> MotionFocus.Region {
        if let text = value.string {
            guard let rect = try? MotionFocus.parse(text) else {
                throw ProjectError.invalid("\(entry): \(field) must be [x, y, width, height] in source pixels")
            }
            return rect
        }
        let numbers = value.array.compactMap(\.double)
        guard numbers.count == 4, value.array.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] >= 1, numbers[3] >= 1 else {
            throw ProjectError.invalid("\(entry): \(field) must be [x, y, width, height] in source pixels")
        }
        return MotionFocus.Region(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// A row's focus, or nil when it gives none; checks it does not also give the zoom, pan and tilt it sets.
    static func decodeFocus(_ row: [String: JSONValue], entry: String) throws -> Focus? {
        func given(_ key: String) -> JSONValue? { row[key].flatMap { $0 == .null ? nil : $0 } }
        let rect = try given("focus").map { try decodeRect($0, entry: entry, field: "focus") }
        let keyRows = given("focusKeys")
        guard rect != nil || keyRows != nil else {
            let stray = ["focusTo", "within", "ease"].filter { given($0) != nil }
            if !stray.isEmpty { throw ProjectError.invalid("\(entry): \(stray.joined(separator: ", ")) need focus or focusKeys") }
            return nil
        }
        let framing = ["zoom", "pan", "tilt"].filter { given($0) != nil }
            + (given("keyframes")?.object.keys.filter { ["zoom", "pan", "tilt"].contains($0) }.sorted() ?? []).map { "keyframes.\($0)" }
        guard framing.isEmpty else {
            throw ProjectError.invalid("\(entry): focus sets zoom, pan and tilt; drop \(framing.joined(separator: ", ")) (null in a patch)")
        }
        var focus = Focus(rect: rect)
        focus.to = try given("focusTo").map { try decodeRect($0, entry: entry, field: "focusTo") }
        if let keyRows {
            guard focus.to == nil else { throw ProjectError.invalid("\(entry): give focusTo or focusKeys, not both") }
            focus.keys = try decodeFocusKeys(keyRows, entry: entry)
        }
        if let within = given("within") { focus.within = try MotionFocus.Within(json: within) }
        if let text = given("ease") {
            guard let name = text.string, let ease = ItemMotion.Ease(rawValue: name) else {
                throw ProjectError.invalid("\(entry): ease must be one of \(ItemMotion.Ease.summary)")
            }
            focus.ease = ease
        }
        return focus
    }

    /// `focusKeys`: 1–200 `{at, rect, move}` with `at` increasing.
    static func decodeFocusKeys(_ value: JSONValue, entry: String) throws -> [FocusKey] {
        guard case .array(let list) = value, (1...200).contains(list.count) else {
            throw ProjectError.invalid("\(entry): focusKeys is a list of 1–200 {at, rect, move}")
        }
        let keys = try list.enumerated().map { index, value in
            let key = value.object
            guard let at = key["at"]?.double, at >= 0, let rect = key["rect"] else {
                throw ProjectError.invalid("\(entry): focusKeys[\(index)] needs at (source seconds) and rect")
            }
            let move = key["move"]?.double
            if let move, !(0...10).contains(move) {
                throw ProjectError.invalid("\(entry): focusKeys[\(index)].move is 0–10 seconds")
            }
            return FocusKey(at: at, rect: try decodeRect(rect, entry: entry, field: "focusKeys[\(index)].rect"), move: move)
        }
        guard zip(keys, keys.dropFirst()).allSatisfy({ $0.at < $1.at }) else {
            throw ProjectError.invalid("\(entry): focusKeys at must increase")
        }
        return keys
    }

    /// The built pictures of a clip whose rows give a focus: its own picture, covers and overlays.
    static func focusTargets(_ clip: Clip) -> [(id: String, focus: Focus)] {
        var targets: [(id: String, focus: Focus?)] = clip.cover.isEmpty ? [("plan-" + clip.id, clip.focus)] : []
        targets += clip.cover.enumerated().map { ("plan-\(clip.id)-cover\($0.offset + 1)", $0.element.focus) }
        targets += clip.overlays.enumerated().map { ("plan-\(clip.id)-overlay\($0.offset + 1)", $0.element.focus) }
        return targets.compactMap { target in target.focus.map { (target.id, $0) } }
    }

    static func builtItem(_ id: String, in project: Project) -> (item: Item, track: Track)? {
        for track in project.tracks {
            if let item = track.items.first(where: { $0.id == id }) { return (item, track) }
        }
        return nil
    }

    /// Sets the zoom, pan and tilt keys of every built picture whose row gives a focus, once all clips and their
    /// overlays are placed (so `within: auto` sees the camera over the screen). Keys of other properties the row's
    /// `keyframes` gives stay.
    static func applyFocus(_ clips: [Resolved], in planner: inout LayerPlanner) throws {
        for clip in clips.map(\.clip) {
            for (id, focus) in focusTargets(clip) {
                guard let (item, track) = builtItem(id, in: planner.project) else { continue }
                let stops = try focusStops(focus, item: item, track: track.id, in: planner.project).stops
                guard !stops.isEmpty else { continue }
                var motion = item.motion ?? ItemMotion(keys: [:])
                motion.keys.merge(MotionFocus.keys(stops, ease: focus.ease)) { $1 }
                let listed = Set(item[pictureTag]?.array.compactMap(\.string) ?? []).union(["keyframes"])
                try planner.add([.setProperties(item: id, patch: [
                    "keyframes": motion.json, pictureTag: .array(listed.sorted().map(JSONValue.string)),
                ])])
            }
        }
    }

    /// A warning per focus key outside the source its shot plays, on the edit as built.
    public static func focusProblems(_ spec: Spec, on project: Project) -> [Problem] {
        spec.clips.flatMap { clip in
            focusTargets(clip).flatMap { id, focus -> [Problem] in
                guard let (item, track) = builtItem(id, in: project),
                    let outside = try? focusStops(focus, item: item, track: track.id, in: project).outside
                else { return [] }
                return outside.map { at in
                    Problem(
                        id: "focus-key-outside", severity: "warning", entry: clip.id,
                        detail: "focusKeys at \(at) s is outside the source seconds \(id) plays, so it frames nothing",
                        facts: ["at": .number(at), "item": .string(id)])
                }
            }
        }
    }

    /// The framings of `focus` on a built `item`, and the `at` of each focus key outside the source it plays.
    static func focusStops(
        _ focus: Focus, item: Item, track: String, in project: Project
    ) throws -> (stops: [MotionFocus.Stop], outside: [Double]) {
        let fps = project.fps.value
        let media = project.media.first { $0.id == item.mediaID }
        let start = media.map { $0.isImage ? 0 : Double(item.sourceIn) / $0.fps.value } ?? 0
        let speed = item.speed > 0 ? item.speed : 1
        let last = max(1, item.duration - 1)
        func framing(_ rect: MotionFocus.Region, at local: Int) throws -> MotionFocus.Framing {
            try project.focusFraming(rect, item: item, track: track, within: focus.within, at: local).framing
        }
        var stops: [MotionFocus.Stop] = []
        if let rect = focus.rect { stops.append(.init(depart: 0, arrive: 0, framing: try framing(rect, at: 0))) }
        if let to = focus.to { stops.append(.init(depart: 0, arrive: last, framing: try framing(to, at: last))) }
        var outside: [Double] = []
        // Keys at or before the shot's first frame: only the last of them shows, from the start.
        let local = focus.keys.map { key in Int((((key.at - start) / speed) * fps).rounded()) }
        let opening = local.lastIndex { $0 <= 0 }
        for (index, key) in focus.keys.enumerated() {
            if local[index] >= item.duration || (local[index] < 0 && index != opening) {
                outside.append(key.at)
                continue
            }
            let at = max(0, local[index])
            if stops.isEmpty {
                stops.append(.init(depart: 0, arrive: 0, framing: try framing(key.rect, at: at)))
                continue
            }
            let move = max(1, Int(((key.move ?? Focus.moveSeconds) * fps).rounded()))
            let arrive = min(last, at + move)
            stops.append(.init(depart: at, arrive: arrive, framing: try framing(key.rect, at: arrive)))
        }
        return (stops, outside)
    }
}
