import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// Keyframe animation (Inspector › Video/Text › Animation and keyframes, Audio › Volume keyframe, `clip motion`,
/// `clip keyframe`). Each change is one undoable `setProperties` edit of the item's `keyframes`.
extension ProjectDocument {
    /// The item `id` (the selection by default) when it can animate: a clip or image on a video layer, text, or
    /// sound (volume only).
    func motionTarget(_ id: String? = nil) throws -> Item {
        try motionTargetAndTrack(id).item
    }

    private func motionTargetAndTrack(_ id: String?) throws -> (item: Item, track: Track) {
        guard let id = id ?? selectedID,
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
            let item = track.items.first(where: { $0.id == id })
        else { throw ProjectError.invalid("Select a clip or text to animate") }
        guard !ItemMotion.properties(onTrackKind: track.kind).isEmpty else {
            throw ProjectError.invalid("Only clips, images, text and audio animate")
        }
        return (item, track)
    }

    /// Replaces an item's animation, or removes it with nil.
    @discardableResult
    func setMotion(
        _ motion: ItemMotion?, item id: String? = nil, label: String = "Animation", author: Author = .user,
        baseRevision: Int? = nil, coalescingKey: String? = nil
    ) throws -> Int {
        let item = try motionTarget(id)
        let value: JSONValue = motion.flatMap { $0.isEmpty ? nil : $0.json } ?? .null
        return try commit(
            .setProperties(item: item.id, patch: ["keyframes": value]), label: label, author: author,
            baseRevision: baseRevision, coalescingKey: coalescingKey)
    }

    /// Applies a `MotionPreset` sized to the item; "none" removes the animation.
    @discardableResult
    func applyMotionPreset(_ preset: String, item id: String? = nil, author: Author = .user, baseRevision: Int? = nil)
        throws -> Int
    {
        let (item, track) = try motionTargetAndTrack(id)
        if preset == "none" {
            return try setMotion(nil, item: item.id, label: "Remove animation", author: author, baseRevision: baseRevision)
        }
        guard track.kind != TrackKind.audio else {
            throw ProjectError.invalid("Presets move pictures; key audio volume with clip keyframe --property volume")
        }
        let motion = try MotionPreset.motion(
            preset, duration: item.duration, width: project.width, height: project.height, fps: project.fps)
        let title = MotionPreset.all.first { $0.id == preset }?.title ?? preset
        return try setMotion(motion, item: item.id, label: title, author: author, baseRevision: baseRevision)
    }

    /// The value `property` has at timeline `frame` (the playhead by default): from its keys, or the static value.
    func motionValue(_ property: String, item: Item, at frame: Int? = nil) -> Double {
        let local = Double((frame ?? playhead) - item.at)
        if let value = item.motion?.value(property, at: local) { return value }
        switch property {
        case "opacity": return item["opacity"]?.double ?? 1
        case "volume": return item["volumeDb"]?.double ?? 0
        case "zoom": return item["transform"]?.object["zoom"]?.double ?? 1
        case let path where path.contains("."):
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            if let value = item[parts[0]]?.object[parts[1]]?.double { return value }
            if parts[0] == "textStyle" {
                let defaults = TextPresetStyle.defaults(item.textPreset).merging(["positionX": 0.5, "lineHeight": 1.28]) { $1 }
                return defaults[parts[1]] ?? 0
            }
            return ["contrast": 1, "saturation": 1, "lutStrength": 1][parts[1]] ?? 0
        default: return item["transform"]?.object[property]?.double ?? 0
        }
    }

    /// Sets (or with `remove`, deletes) the key of `property` at timeline `frame` (the playhead by default), keeping
    /// the other keys. Values are clamped to the property's range.
    @discardableResult
    func setKeyframe(
        _ property: String, value: Double?, at frame: Int? = nil, ease: ItemMotion.Ease? = nil, remove: Bool = false,
        item id: String? = nil, author: Author = .user, baseRevision: Int? = nil, coalesce: Bool = false
    ) throws -> Int {
        guard let range = ItemMotion.ranges[property] else {
            throw ProjectError.invalid("Unknown property \(property); use \(ItemMotion.ranges.keys.sorted().joined(separator: ", "))")
        }
        let (item, track) = try motionTargetAndTrack(id)
        let allowed = ItemMotion.properties(onTrackKind: track.kind)
        guard allowed.contains(property) else {
            throw ProjectError.invalid(
                "\(track.kind.capitalized) items animate \(allowed.joined(separator: ", ")), not \(property)")
        }
        let local = (frame ?? playhead) - item.at
        guard (0..<item.duration).contains(local) else {
            throw ProjectError.invalid("Move the playhead inside the item to set a keyframe")
        }
        var motion = item.motion ?? ItemMotion(keys: [:])
        var keys = (motion.keys[property] ?? []).filter { $0.frame != local }
        if !remove {
            let current = motionValue(property, item: item, at: item.at + local)
            let clamped = min(range.upperBound, max(range.lowerBound, value ?? current))
            let previous = item.motion?.keys[property]?.first { $0.frame == local }
            keys.append(.init(frame: local, value: clamped, ease: ease ?? previous?.ease ?? .easeInOut))
            keys.sort { $0.frame < $1.frame }
        }
        motion.keys[property] = keys.isEmpty ? nil : keys
        return try setMotion(
            motion, item: item.id, label: remove ? "Remove keyframe" : "Keyframe", author: author,
            baseRevision: baseRevision, coalescingKey: coalesce ? "keyframe.\(item.id).\(property).\(local)" : nil)
    }

    /// Keys every property that moves the item's picture (volume on audio items) at the playhead with its current
    /// value (Inspector's diamond).
    @discardableResult
    func keyframeAll(
        item id: String? = nil, at frame: Int? = nil, properties: [String]? = nil, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> Int {
        let (item, track) = try motionTargetAndTrack(id)
        let local = (frame ?? playhead) - item.at
        guard (0..<item.duration).contains(local) else {
            throw ProjectError.invalid("Move the playhead inside the item to set a keyframe")
        }
        var motion = item.motion ?? ItemMotion(keys: [:])
        for property in properties ?? (track.kind == TrackKind.audio ? ["volume"] : ItemMotion.pictureProperties) {
            let value = motionValue(property, item: item, at: item.at + local)
            var keys = (motion.keys[property] ?? []).filter { $0.frame != local }
            keys.append(.init(frame: local, value: value))
            motion.keys[property] = keys.sorted { $0.frame < $1.frame }
        }
        return try setMotion(motion, item: item.id, label: "Keyframe", author: author, baseRevision: baseRevision)
    }

    /// Frames a rectangle of a video clip's picture with zoom, pan and tilt keys (moving to `target` by the last
    /// frame when given) inside `within`'s band of the canvas, keeping the item's other keys. Returns the revision and
    /// the band (canvas pixels) the first framing landed in.
    @discardableResult
    func applyFocus(
        _ focus: String, to target: String? = nil, within: MotionFocus.Within = .auto,
        ease: ItemMotion.Ease = .easeInOut, item id: String? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, band: MotionFocus.Region) {
        let (item, track) = try motionTargetAndTrack(id)
        guard track.kind == TrackKind.video else {
            throw ProjectError.invalid("focus frames a video clip or image whose media has a known size")
        }
        let last = max(1, item.duration - 1)
        let start = try project.focusFraming(MotionFocus.parse(focus), item: item, track: track.id, within: within, at: 0)
        var stops = [MotionFocus.Stop(depart: 0, arrive: 0, framing: start.framing)]
        if let target {
            let end = try project.focusFraming(
                MotionFocus.parse(target), item: item, track: track.id, within: within, at: last)
            stops.append(.init(depart: 0, arrive: last, framing: end.framing))
        }
        var motion = item.motion ?? ItemMotion(keys: [:])
        motion.keys.merge(MotionFocus.keys(stops, ease: ease)) { $1 }
        let revision = try setMotion(motion, item: item.id, label: "Focus", author: author, baseRevision: baseRevision)
        return (revision, start.band)
    }

    func registerMotionCommands() {
        handleAuthored("clip.motion") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            let base = try arguments.int("baseRev")
            let revision: Int
            if let focus = arguments.optionalString("focus") {
                let ease = try arguments.optionalString("ease").map { text -> ItemMotion.Ease in
                    guard let ease = ItemMotion.Ease(rawValue: text) else { throw RPCFailure(-32602, "Unknown ease \(text)") }
                    return ease
                }
                let within: MotionFocus.Within
                do { within = try MotionFocus.Within(arguments.optionalString("within") ?? "auto") } catch {
                    throw RPCFailure.from(error, fallbackCode: -32602)
                }
                let focused = try document.applyFocus(
                    focus, to: arguments.optionalString("focusTo"), within: within, ease: ease ?? .easeInOut, item: id,
                    author: author, baseRevision: base)
                let item = try document.motionTarget(id)
                return .object([
                    "rev": .integer(focused.revision), "item": .string(item.id), "keyframes": item["keyframes"] ?? .null,
                    "within": focused.band.json,
                ])
            } else if arguments.optionalString("focusTo") != nil || arguments.optionalString("within") != nil {
                throw RPCFailure(-32602, "focus-to and within need focus")
            } else if let text = arguments.optionalString("keyframes") {
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
                    throw RPCFailure(-32602, "keyframes must be a JSON object")
                }
                let motion: ItemMotion
                do { motion = try ItemMotion(json: json) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
                revision = try document.setMotion(motion, item: id, author: author, baseRevision: base)
            } else if let preset = arguments.optionalString("preset") {
                revision = try document.applyMotionPreset(preset, item: id, author: author, baseRevision: base)
            } else {
                throw RPCFailure(-32602, "Give a preset (or none), keyframes or focus")
            }
            let item = try document.motionTarget(id)
            return .object(["rev": .integer(revision), "item": .string(item.id), "keyframes": item["keyframes"] ?? .null])
        }
        handleAuthored("clip.keyframe") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            let ease = try arguments.optionalString("ease").map { text -> ItemMotion.Ease in
                guard let ease = ItemMotion.Ease(rawValue: text) else { throw RPCFailure(-32602, "Unknown ease \(text)") }
                return ease
            }
            let base = try arguments.int("baseRev")
            let revision: Int
            if let property = arguments.optionalString("property") {
                revision = try document.setKeyframe(
                    property, value: arguments.optionalDouble("value"), at: arguments.optionalInt("atFrame"), ease: ease,
                    remove: arguments.bool("remove"), item: id, author: author, baseRevision: base)
            } else {
                revision = try document.keyframeAll(
                    item: id, at: arguments.optionalInt("atFrame"), author: author, baseRevision: base)
            }
            let item = try document.motionTarget(id)
            return .object(["rev": .integer(revision), "item": .string(item.id), "keyframes": item["keyframes"] ?? .null])
        }
    }
}
