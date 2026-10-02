import BashCutAutomation
import BashCutProject
import Foundation

/// Adjustment items and style kits, shared by the Filters library and automation.
extension ProjectDocument {
    /// The range a new adjustment covers when none is given: the selected clip, else 3 seconds at the playhead.
    private var defaultAdjustmentRange: Range<Int> {
        if let item = selected, selectedItemTrack?.isAdjustment == false { return item.at..<item.end }
        return playhead..<(playhead + max(1, Int((3 * project.fps.value).rounded())))
    }

    /// Adds an adjustment item with `look` (and a LUT) on an adjustment layer, adding the layer when needed.
    @discardableResult
    func addAdjustment(
        look: ColorLook = ColorLook.all[0], lutID: String? = nil, at frame: Int? = nil, duration: Int? = nil,
        trackID: String? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, itemID: String, trackID: String) {
        var color = look.color
        if let lutID {
            guard project.colorLUTs.contains(where: { $0.id == lutID }) else {
                throw ProjectError.invalid("Unknown LUT \(lutID)")
            }
            color["lut"] = .string(lutID)
        }
        if let trackID, project.track(id: trackID)?.isAdjustment != true {
            throw ProjectError.invalid("Layer \(trackID) is not an adjustment layer")
        }
        let range = defaultAdjustmentRange
        let item = Item.adjustment(
            at: frame ?? range.lowerBound, duration: duration ?? range.count, color: color)
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
        do { try addAdjustment(look: look) } catch { message = error.localizedDescription }
    }

    func runStyleKit(_ kit: StyleKit) {
        do { try applyStyleKit(kit) } catch { message = error.localizedDescription }
    }

    // MARK: Automation

    func registerAdjustmentCommands() {
        handleAuthored("adjustment.add") { document, arguments, author in
            let lookID = try arguments.string("look")
            guard let look = ColorLook.named(lookID) else { throw RPCFailure(-32602, "Unknown look \(lookID)") }
            let result = try document.addAdjustment(
                look: look, lutID: arguments.optionalString("lut"), at: arguments.optionalInt("atFrame"),
                duration: arguments.optionalInt("duration"), trackID: arguments.optionalString("track"),
                author: author, baseRevision: arguments.int("baseRev"))
            return .object([
                "rev": .integer(result.revision), "item": .string(result.itemID), "track": .string(result.trackID),
            ])
        }
        handleAuthored("style.apply") { document, arguments, author in
            let kitID = try arguments.string("kit")
            guard let kit = StyleKit.named(kitID) else { throw RPCFailure(-32602, "Unknown style kit \(kitID)") }
            let result = try document.applyStyleKit(kit, author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "item": .string(result.itemID)])
        }
    }
}
