import Foundation

extension Project {
    mutating func addColorLUT(_ lut: ColorLUT) throws {
        guard !colorLUTs.contains(where: { $0.id == lut.id || $0.path == lut.path }) else {
            throw ProjectError.invalid("LUT already exists")
        }
        colorLUTs.append(lut)
    }

    mutating func deleteColorLUT(id: String) throws {
        var values = colorLUTs
        guard let index = values.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown LUT: \(id)")
        }
        values.remove(at: index)
        colorLUTs = values
        var trackValues = tracks
        for trackIndex in trackValues.indices {
            var items = trackValues[trackIndex].items
            for itemIndex in items.indices {
                var color = items[itemIndex].fields["color"]?.object ?? [:]
                if color["lut"]?.string == id {
                    color.removeValue(forKey: "lut")
                    color.removeValue(forKey: "lutStrength")
                    items[itemIndex].fields["color"] = .object(color)
                }
            }
            trackValues[trackIndex].items = items
        }
        tracks = trackValues
    }
}
