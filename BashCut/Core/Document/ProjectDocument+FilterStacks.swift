import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// Filter stacks (#79): a look library item is a grade plus, optionally, its own .cube LUT. Placing it adds an
/// adjustment and applying it grades a clip or adjustment; either is one undo step that also adds the LUT to the
/// project when it is not there yet.
extension ProjectDocument {
    /// Places a look as an adjustment item: the given range, else the selected clip's or 3 seconds at the playhead.
    func placeFilterStack(
        _ item: LibraryItem, _ placement: LibraryPlacement
    ) async throws -> (revision: Int, itemID: String) {
        let stack = try filterStack(item)
        if let trackID = placement.trackID, project.track(id: trackID)?.isAdjustment != true {
            throw RPCFailure(-32602, "Layer \(trackID) is not an adjustment layer")
        }
        let lut = try await filterStackLUT(item, stack)
        let range = defaultAdjustmentRange
        let adjustment = Item.adjustment(
            at: placement.frame ?? range.lowerBound, duration: placement.duration ?? range.count)
        let planner: LayerPlanner
        do {
            planner = try project.filterStackPlacePlan(stack, lut: lut, item: adjustment, on: placement.trackID)
        } catch { throw RPCFailure(-32602, error.localizedDescription) }
        let revision = try commitPlan(
            planner, label: item.name, author: placement.author, baseRevision: placement.baseRevision)
        selectedID = adjustment.id
        selectedTrackID = project.tracks.first { $0.items.contains { $0.id == adjustment.id } }?.id
        return (revision, adjustment.id)
    }

    /// Grades the clip or adjustment `itemID` with a look, replacing its grade.
    func applyFilterStack(_ item: LibraryItem, to itemID: String, author: Author, baseRevision: Int?) async throws -> Int {
        let stack = try filterStack(item)
        let lut = try await filterStackLUT(item, stack)
        let planner: LayerPlanner
        do { planner = try project.filterStackApplyPlan(stack, lut: lut, to: itemID) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        return try commitPlan(planner, label: item.name, author: author, baseRevision: baseRevision)
    }

    private func filterStack(_ item: LibraryItem) throws -> FilterStack {
        do { return try FilterStack(params: item.params, label: item.reference) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
    }

    /// The project LUT for a look's own .cube: the one already copied from the same file (same SHA-256), else a new
    /// entry for its copy in the project's `luts` folder. Nil for a look without a file.
    private func filterStackLUT(_ item: LibraryItem, _ stack: FilterStack) async throws -> ColorLUT? {
        guard item.file != nil else { return nil }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before using a look with a LUT")
        }
        guard let file = libraryCatalog.fileURL(of: item) else { throw RPCFailure(-32602, "\(item.reference) has no file") }
        let copy = try await LibraryWorker.shared.run { try Self.projectLUTCopy(of: file, root: root) }
        if let existing = project.libraryLUT(sha256: copy.sha256) ?? project.colorLUTs.first(where: { $0.path == copy.path }) {
            return existing
        }
        var lut = ColorLUT(name: String((stack.lutName ?? item.name).prefix(120)), path: copy.path, size: copy.size)
        lut[ColorLUT.libraryHashField] = .string(copy.sha256)
        lut[ColorLUT.libraryItemField] = .string(item.reference)
        return lut
    }

    /// Checks a library .cube and copies it to `luts/library-<hash>.cube` in the project, once per content.
    nonisolated static func projectLUTCopy(of file: URL, root: URL) throws -> (path: String, sha256: String, size: Int) {
        let parsed = try CubeLUT.load(file)
        let digest = try LibraryStore.sha256(of: file)
        let path = "luts/library-\(digest.prefix(16)).cube"
        let target = root.appendingPathComponent(path)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: target)
        }
        return (path, digest, parsed.dimension)
    }

    /// The project LUT the item `item` is graded with, and its file, for saving its look with the LUT.
    func gradeLUT(of item: Item?) -> (lut: ColorLUT, file: URL)? {
        guard let id = item?["color"]?.object["lut"]?.string, let lut = project.colorLUTs.first(where: { $0.id == id }),
            let root = fileURL?.deletingLastPathComponent()
        else { return nil }
        let file = root.appendingPathComponent(lut.path)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return (lut, file)
    }
}
