import BashCutAutomation
import BashCutProject
import Foundation

/// Adjustment items, shared by the Filters library and automation.
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

    /// The grade of a library look without a file; a look with a LUT file goes through `library place`.
    private func adjustmentLook(_ reference: String) throws -> [String: JSONValue] {
        let item: LibraryItem
        do { item = try libraryCatalog.item(reference) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        guard item.kind == .look else { throw RPCFailure(-32602, "\(reference) is not a look") }
        guard item.file == nil else {
            throw RPCFailure(-32602, "\(item.reference) has a LUT file; use library place \(item.reference)")
        }
        do { return try FilterStack(params: item.params, label: item.reference).color } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
    }

    /// Projects saved before looks were library items (C8) keep their own looks in `looks`: copies each one into the
    /// project library once (an ID already there is left alone). The project field stays as it was.
    func copyProjectLooksToLibrary() {
        guard case .array(let looks) = project["looks"], !looks.isEmpty, fileURL != nil else { return }
        let catalog = libraryCatalog
        for entry in looks {
            let fields = entry.object
            guard let id = fields["id"]?.string, (try? catalog.item(id, scope: .project)) == nil else { continue }
            let item = LibraryItem(
                id: id, kind: .look, name: fields["title"]?.string ?? id, pack: "Project looks",
                params: FilterStack(color: fields["color"]?.object ?? [:]).params)
            do { try catalog.add(item, into: .project) } catch {
                DebugLog.write("library", "project look \(id) not copied: \(error.localizedDescription)")
            }
        }
    }

    func registerAdjustmentCommands() {
        handleAuthored("adjustment.add") { document, arguments, author in
            let look = try document.adjustmentLook(arguments.string("look"))
            let result = try document.addAdjustment(
                color: document.grade(look, arguments), at: arguments.optionalInt("atFrame"),
                duration: arguments.optionalInt("duration"), trackID: arguments.optionalString("track"),
                author: author, baseRevision: arguments.int("baseRev"))
            return .object([
                "rev": .integer(result.revision), "item": .string(result.itemID), "track": .string(result.trackID),
            ])
        }
        handle("schema.get") { _, _, _ in ProjectSchema.document }
    }
}
