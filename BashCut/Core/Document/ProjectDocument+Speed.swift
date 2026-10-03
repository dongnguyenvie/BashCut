import BashCutAutomation
import BashCutProject
import Foundation

/// Constant clip speed: Inspector › Speed, the clip menu, Speed up / Slow down and `clip.speed` all end in
/// `setClipSpeed`, one undoable edit.
extension ProjectDocument {
    /// The selected clip when its speed can change (it has media and is not a freeze frame).
    var speedTarget: Item? {
        guard let item = selected, item.mediaID != nil, item.fields["freezeFrame"] == nil else { return nil }
        return item
    }

    /// The length a clip would have at `speed`, before it is shortened to fit its source.
    func duration(of item: Item, at speed: Double, keepDuration: Bool) -> Int {
        keepDuration ? item.duration : max(1, Int((Double(item.duration) * item.speed / speed).rounded()))
    }

    /// Changes a clip's speed (and optionally pitch preservation) as one edit. Dragging the slider repeatedly on the
    /// same clip coalesces into one undo step.
    @discardableResult
    func setClipSpeed(
        _ speed: Double, item id: String? = nil, keepDuration: Bool, preservePitch: Bool? = nil, author: Author = .user,
        baseRevision: Int? = nil, coalesce: Bool = false
    ) throws -> Int {
        guard let id = id ?? selectedID else { throw ProjectError.invalid("Select a clip to change its speed") }
        // The same speed (and no pitch change) is not an edit: it would only add an undo step that changes nothing.
        if preservePitch == nil, let current = project.tracks.flatMap(\.items).first(where: { $0.id == id }),
            abs(current.speed - speed) < 0.0001
        {
            return project.revision
        }
        var operations: [EditOperation] = [.setSpeed(item: id, speed: speed, keepDuration: keepDuration)]
        if let preservePitch {
            operations.append(.setProperties(item: id, patch: ["preservePitch": .bool(preservePitch)]))
            if let linked = project.tracks.flatMap(\.items).first(where: { $0.id == id })?.linkedItemID {
                operations.append(.setProperties(item: linked, patch: ["preservePitch": .bool(preservePitch)]))
            }
        }
        let label = "Speed " + UIAction.speedLabel(speed)
        return try commit(
            .group(label: label, author: author, ops: operations), label: label, author: author,
            baseRevision: baseRevision, coalescingKey: coalesce ? "speed.\(id)" : nil)
    }

    /// The next preset above or below the selected clip's speed (Speed up / Slow down).
    func stepSpeed(up: Bool, author: Author) throws {
        guard let item = speedTarget else { throw ProjectError.invalid("Select a clip to change its speed") }
        let presets = UIAction.speedPresets
        let next = up ? presets.first { $0 > item.speed + 0.001 } : presets.last { $0 < item.speed - 0.001 }
        guard let next else { return }
        try setClipSpeed(next, keepDuration: false, author: author)
    }

    func registerSpeedCommands() {
        handleAuthored("clip.speed") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            guard let id else { throw RPCFailure(-32602, "Give an item or select a clip first") }
            let speed = arguments.optionalDouble("speed") ?? 1
            let revision = try document.setClipSpeed(
                speed, item: id, keepDuration: arguments.bool("keepDuration"),
                preservePitch: arguments.optionalBool("preservePitch"), author: author,
                baseRevision: try arguments.int("baseRev"))
            let item = document.project.tracks.flatMap(\.items).first { $0.id == id }
            return .object([
                "rev": .integer(revision), "item": .string(id), "speed": .number(item?.speed ?? speed),
                "duration": item.map { .integer($0.duration) } ?? .null,
                "linked": item?.linkedItemID.map(JSONValue.string) ?? .null,
            ])
        }
    }
}
