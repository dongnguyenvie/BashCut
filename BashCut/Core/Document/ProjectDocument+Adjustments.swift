import BashCutAutomation
import BashCutProject
import Foundation

/// Adjustment items, looks and style kits, shared by the Filters library and automation.
extension ProjectDocument {
    /// The range a new adjustment covers when none is given: the selected clip, else 3 seconds at the playhead.
    var defaultAdjustmentRange: Range<Int> {
        if let item = selected, selectedItemTrack?.isAdjustment == false { return item.at..<item.end }
        return playhead..<(playhead + max(1, Int((3 * project.fps.value).rounded())))
    }

    /// Adds an adjustment item graded with `color` on an adjustment layer, adding the layer when needed.
    @discardableResult
    func addAdjustment(
        color: [String: JSONValue] = [:], at frame: Int? = nil, duration: Int? = nil, trackID: String? = nil,
        author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, itemID: String, trackID: String) {
        if let trackID, project.track(id: trackID)?.isAdjustment != true {
            throw ProjectError.invalid("Layer \(trackID) is not an adjustment layer")
        }
        let range = defaultAdjustmentRange
        let item = Item.adjustment(at: frame ?? range.lowerBound, duration: duration ?? range.count, color: color)
        var planner = LayerPlanner(project)
        let used = try planner.placeAdjustment(item, on: trackID)
        let revision = try commitPlan(planner, label: "Add adjustment", author: author, baseRevision: baseRevision)
        selectedID = item.id
        selectedTrackID = used
        return (revision, item.id, used)
    }

    /// Applies a style kit as one undoable edit and selects the adjustment item it added.
    @discardableResult
    func applyStyleKit(
        _ kit: StyleKit, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, itemID: String) {
        let itemID = UUID().uuidString
        let label = "Apply \(kit.title) style"
        let revision = try commit(
            .group(label: label, author: author, ops: project.styleKitOperations(kit, itemID: itemID)),
            label: label, author: author, baseRevision: baseRevision)
        selectedID = itemID
        return (revision, itemID)
    }

    /// Filters library: grades the selected clip or adjustment item, or adds an adjustment when none is selected.
    func applyLook(_ look: ColorLook) {
        guard selected == nil else { return patchSelected(["color": .object(look.color)], label: look.title) }
        do { try addAdjustment(color: look.color) } catch { message = error.localizedDescription }
    }

    func runStyleKit(_ kit: StyleKit) {
        do { try applyStyleKit(kit) } catch { message = error.localizedDescription }
    }

    func deleteCustomLook(_ look: ColorLook) {
        do { try commit(project.deletingLook(look.id), label: "Delete look") } catch { message = error.localizedDescription }
    }

    func deleteCustomStyleKit(_ kit: StyleKit) {
        do {
            try commit(project.deletingStyleKit(kit.id), label: "Delete style kit")
        } catch { message = error.localizedDescription }
    }

    // MARK: Automation

    /// A grade from a starting color plus the command's grade options (`exposure`, …, `lut`).
    private func grade(_ base: [String: JSONValue], _ arguments: CommandArguments) -> [String: JSONValue] {
        var color = base
        for (key, _) in ColorGrade.ranges {
            if let value = arguments.optionalDouble(key) { color[key] = .number(value) }
        }
        if let lut = arguments.optionalString("lut") { color["lut"] = .string(lut) }
        return color
    }

    func registerAdjustmentCommands() {
        handleAuthored("adjustment.add") { document, arguments, author in
            let lookID = try arguments.string("look")
            guard let look = document.project.look(lookID) else { throw RPCFailure(-32602, "Unknown look \(lookID)") }
            let result = try document.addAdjustment(
                color: document.grade(look.color, arguments), at: arguments.optionalInt("atFrame"),
                duration: arguments.optionalInt("duration"), trackID: arguments.optionalString("track"),
                author: author, baseRevision: arguments.int("baseRev"))
            return .object([
                "rev": .integer(result.revision), "item": .string(result.itemID), "track": .string(result.trackID),
            ])
        }
        handleAuthored("style.apply") { document, arguments, author in
            let kitID = try arguments.string("kit")
            guard let kit = document.project.styleKit(kitID) else {
                throw RPCFailure(-32602, "Unknown style kit \(kitID)")
            }
            let result = try document.applyStyleKit(kit, author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "item": .string(result.itemID)])
        }
        handleAuthored("looks.save") { document, arguments, author in
            var base: [String: JSONValue] = [:]
            if let itemID = arguments.optionalString("item") {
                guard let item = document.project.tracks.flatMap(\.items).first(where: { $0.id == itemID }) else {
                    throw RPCFailure(-32602, "Unknown item \(itemID)")
                }
                base = item["color"]?.object ?? [:]
            }
            let look = ColorLook(
                id: try arguments.string("id"), title: try arguments.string("title"),
                color: document.grade(base, arguments))
            let revision = try document.commit(
                document.project.savingLook(look), label: "Save look", author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision), "look": look.json])
        }
        handleAuthored("looks.delete") { document, arguments, author in
            let revision = try document.commit(
                document.project.deletingLook(arguments.string("id")), label: "Delete look", author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
        handleAuthored("style.save") { document, arguments, author in
            let kit = StyleKit(
                id: try arguments.string("id"), title: try arguments.string("title"),
                lookID: try arguments.string("look"), captionPreset: try arguments.string("captionPreset"))
            let revision = try document.commit(
                document.project.savingStyleKit(kit), label: "Save style kit", author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision), "kit": kit.json])
        }
        handleAuthored("style.delete") { document, arguments, author in
            let revision = try document.commit(
                document.project.deletingStyleKit(arguments.string("id")), label: "Delete style kit", author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
        handle("schema.get") { _, _, _ in ProjectSchema.document }
    }
}
