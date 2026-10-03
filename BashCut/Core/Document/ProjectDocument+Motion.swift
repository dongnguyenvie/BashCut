import BashCutAutomation
import BashCutProject
import Foundation

/// Keyframe animation (Inspector › Video/Text › Animation and keyframes, `clip motion`, `clip keyframe`). Each change
/// is one undoable `setProperties` edit of the item's `keyframes`.
extension ProjectDocument {
    /// The item `id` (the selection by default) when it can animate: a clip or image on a video layer, or text.
    func motionTarget(_ id: String? = nil) throws -> Item {
        guard let id = id ?? selectedID,
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
            let item = track.items.first(where: { $0.id == id })
        else { throw ProjectError.invalid("Select a clip or text to animate") }
        guard track.kind == TrackKind.video || track.kind == TrackKind.text else {
            throw ProjectError.invalid("Only clips, images and text animate")
        }
        return item
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
        let item = try motionTarget(id)
        if preset == "none" {
            return try setMotion(nil, item: item.id, label: "Remove animation", author: author, baseRevision: baseRevision)
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
        case "zoom": return item["transform"]?.object["zoom"]?.double ?? 1
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
        let item = try motionTarget(id)
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

    /// Keys every animatable property of the item at the playhead with its current value (Inspector's diamond).
    @discardableResult
    func keyframeAll(
        item id: String? = nil, at frame: Int? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        let item = try motionTarget(id)
        let local = (frame ?? playhead) - item.at
        guard (0..<item.duration).contains(local) else {
            throw ProjectError.invalid("Move the playhead inside the item to set a keyframe")
        }
        var motion = item.motion ?? ItemMotion(keys: [:])
        for property in ItemMotion.ranges.keys.sorted() {
            let value = motionValue(property, item: item, at: item.at + local)
            var keys = (motion.keys[property] ?? []).filter { $0.frame != local }
            keys.append(.init(frame: local, value: value))
            motion.keys[property] = keys.sorted { $0.frame < $1.frame }
        }
        return try setMotion(motion, item: item.id, label: "Keyframe", author: author, baseRevision: baseRevision)
    }

    func registerMotionCommands() {
        handleAuthored("clip.motion") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            let base = try arguments.int("baseRev")
            let revision: Int
            if let text = arguments.optionalString("keyframes") {
                guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
                    throw RPCFailure(-32602, "keyframes must be a JSON object")
                }
                let motion: ItemMotion
                do { motion = try ItemMotion(json: json) } catch { throw RPCFailure(-32602, error.localizedDescription) }
                revision = try document.setMotion(motion, item: id, author: author, baseRevision: base)
            } else if let preset = arguments.optionalString("preset") {
                revision = try document.applyMotionPreset(preset, item: id, author: author, baseRevision: base)
            } else {
                throw RPCFailure(-32602, "Give a preset (or none) or keyframes")
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
