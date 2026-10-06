import Foundation

/// A look's params as a filter stack (#79): the grade an adjustment layer or clip gets, plus an optional LUT.
///
/// `color` is required and holds the grade keys of `ColorGrade.ranges` (exposure, contrast, saturation and
/// `lutStrength`, the LUT mix); other keys round-trip. The LUT itself is the item's own `file`, a .cube that travels
/// with the item and is added to a project's LUTs when the look is used; `lutName` names that project LUT (the item's
/// name when absent). A look without a file is a plain grade and behaves as looks always did.
public struct FilterStack: Sendable, Equatable {
    public var color: [String: JSONValue]
    public var lutName: String?

    public init(color: [String: JSONValue] = [:], lutName: String? = nil) {
        self.color = color
        self.lutName = lutName
    }

    /// Reads and checks `params`; `label` starts each error message.
    public init(params: [String: JSONValue], label: String = "look") throws {
        guard case .object(let color) = params["color"] ?? .null else {
            throw ProjectError.invalid("\(label): a look needs params.color")
        }
        for (key, range) in ColorGrade.ranges {
            guard let value = color[key] else { continue }
            guard let number = value.double, number.isFinite, range.contains(number) else {
                throw ProjectError.invalid("\(label): params.color.\(key) must be a number in \(range)")
            }
        }
        self.color = color
        if let value = params["lutName"] {
            guard let name = value.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120
            else { throw ProjectError.invalid("\(label): params.lutName must be 1–120 characters") }
            lutName = name
        }
    }

    /// The params as a library item stores them.
    public var params: [String: JSONValue] {
        var params: [String: JSONValue] = ["color": .object(color)]
        if let lutName { params["lutName"] = .string(lutName) }
        return params
    }

    /// The grade to set on an item: `color`, pointing at the project LUT `lutID` when the stack has a LUT. Without
    /// one, `color` is used as stored, as plain looks always were.
    public func grade(lutID: String?) -> [String: JSONValue] {
        guard let lutID else { return color }
        var grade = color
        grade["lut"] = .string(lutID)
        return grade
    }

    /// A library look's LUT file must be a .cube.
    static func isLUTFile(_ path: String) -> Bool { path.lowercased().hasSuffix(".cube") }
}

extension Project {
    /// The project LUT made from a library .cube with this SHA-256 (`ColorLUT.libraryHashField`), so using a look
    /// again reuses it instead of adding a copy.
    public func libraryLUT(sha256: String) -> ColorLUT? {
        colorLUTs.first { $0[ColorLUT.libraryHashField]?.string == sha256 }
    }

    /// The plan that places `stack` as the adjustment `item` (its range set by the caller), on `trackID` or the first
    /// adjustment layer: one edit that also adds `lut` (a stack's LUT, new or already in the project) when needed.
    public func filterStackPlacePlan(
        _ stack: FilterStack, lut: ColorLUT? = nil, item: Item, on trackID: String? = nil
    ) throws -> LayerPlanner {
        var planner = LayerPlanner(self)
        try planner.addLUTIfNeeded(lut)
        var adjustment = item
        adjustment["color"] = .object(stack.grade(lutID: lut?.id))
        try planner.placeAdjustment(adjustment, on: trackID)
        return planner
    }

    /// The plan that grades the clip or adjustment `itemID` with `stack`, replacing its grade: one edit that also
    /// adds `lut` when needed.
    public func filterStackApplyPlan(_ stack: FilterStack, lut: ColorLUT? = nil, to itemID: String) throws -> LayerPlanner {
        guard tracks.contains(where: { $0.items.contains { $0.id == itemID } }) else {
            throw ProjectError.invalid("Unknown item \(itemID)")
        }
        var planner = LayerPlanner(self)
        try planner.addLUTIfNeeded(lut)
        try planner.add([.setProperties(item: itemID, patch: ["color": .object(stack.grade(lutID: lut?.id))])])
        return planner
    }
}

extension ColorLUT {
    /// The field that keeps the SHA-256 of the library .cube a LUT was copied from.
    public static let libraryHashField = "sha256"
    /// The field naming the library item (`scope:id`) a LUT was copied from.
    public static let libraryItemField = "libraryItem"
}

extension LayerPlanner {
    fileprivate mutating func addLUTIfNeeded(_ lut: ColorLUT?) throws {
        guard let lut, !project.colorLUTs.contains(where: { $0.id == lut.id }) else { return }
        try add([.addColorLUT(lut)])
    }
}
