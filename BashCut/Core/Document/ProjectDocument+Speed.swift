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
            current.speedCurve == nil, abs(current.speed - speed) < 0.0001
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

    /// Changes several clips' speed as one undo step (the multi-selection Inspector, `clip.speed --items`): each clip
    /// with the single-clip rules (its length follows unless keepDuration, rippling its layer; linked sound follows).
    /// Items whose speed cannot change are left out and returned as `skipped`; throws when none can.
    @discardableResult
    func setClipSpeeds(
        _ speed: Double, items ids: [String], keepDuration: Bool, preservePitch: Bool? = nil, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> (revision: Int, skipped: [String]) {
        var (operations, skipped) = project.speedOperations(ids, speed: speed, keepDuration: keepDuration)
        guard !operations.isEmpty else {
            throw ProjectError.invalid("None of the items is a clip whose speed can change (media, not a freeze frame)")
        }
        if let preservePitch {
            let changed = operations.compactMap { operation -> String? in
                if case .setSpeed(let id, _, _) = operation { return id }
                return nil
            }
            let items = project.tracks.flatMap(\.items)
            for id in changed {
                let linked = items.first { $0.id == id }?.linkedItemID
                for target in [id] + (linked.map { [$0] } ?? []) {
                    operations.append(.setProperties(item: target, patch: ["preservePitch": .bool(preservePitch)]))
                }
            }
        }
        let label = "Speed " + UIAction.speedLabel(speed)
        let revision = try commit(
            .group(label: label, author: author, ops: operations), label: label, author: author,
            baseRevision: baseRevision)
        return (revision, skipped)
    }

    /// The next preset above or below the selected clip's speed (Speed up / Slow down).
    func stepSpeed(up: Bool, author: Author) throws {
        guard let item = speedTarget else { throw ProjectError.invalid("Select a clip to change its speed") }
        let presets = UIAction.speedPresets
        let next = up ? presets.first { $0 > item.speed + 0.001 } : presets.last { $0 < item.speed - 0.001 }
        guard let next else { return }
        try setClipSpeed(next, keepDuration: false, author: author)
    }

    /// Whether a keepDuration change still had to shorten the clip because its source ran out.
    static func shortened(before: Int?, after: Int?, keepDuration: Bool) -> Bool {
        guard keepDuration, let before, let after else { return false }
        return after < before
    }

    func registerSpeedCommands() {
        handleAuthored("clip.speed") { document, arguments, author in
            let listed = (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !listed.isEmpty { return try document.clipSpeeds(listed, arguments, author: author) }
            let id = arguments.optionalString("item") ?? document.selectedID
            guard let id else { throw RPCFailure(-32602, "Give an item or select a clip first") }
            let speed = arguments.optionalDouble("speed") ?? 1
            let before = document.project.tracks.flatMap(\.items).first { $0.id == id }?.duration
            let revision = try document.setClipSpeed(
                speed, item: id, keepDuration: arguments.bool("keepDuration"),
                preservePitch: arguments.optionalBool("preservePitch"), author: author,
                baseRevision: try arguments.int("baseRev"))
            let item = document.project.tracks.flatMap(\.items).first { $0.id == id }
            return .object([
                "rev": .integer(revision), "item": .string(id), "speed": .number(item?.speed ?? speed),
                "duration": item.map { .integer($0.duration) } ?? .null,
                "linked": item?.linkedItemID.map(JSONValue.string) ?? .null,
                "shortened": .bool(Self.shortened(before: before, after: item?.duration, keepDuration: arguments.bool("keepDuration"))),
            ])
        }
    }

    /// `clip.speed --items`: several clips in one undo step; each row as `clip.speed` reports one clip.
    private func clipSpeeds(_ ids: [String], _ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let keepDuration = arguments.bool("keepDuration")
        let speed = arguments.optionalDouble("speed") ?? 1
        let items = { Dictionary(self.project.tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first } }
        let before = items()
        let (revision, skipped) = try setClipSpeeds(
            speed, items: ids, keepDuration: keepDuration, preservePitch: arguments.optionalBool("preservePitch"),
            author: author, baseRevision: try arguments.int("baseRev"))
        let after = items()
        let rows: [JSONValue] = ids.filter { !skipped.contains($0) }.compactMap { id in
            guard let item = after[id] else { return nil }
            return .object([
                "item": .string(id), "speed": .number(item.speed), "duration": .integer(item.duration),
                "shortened": .bool(Self.shortened(before: before[id]?.duration, after: item.duration, keepDuration: keepDuration)),
            ])
        }
        return .object(["rev": .integer(revision), "items": .array(rows), "skipped": .array(skipped.map(JSONValue.string))])
    }
}
