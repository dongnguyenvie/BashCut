import Foundation

// Color grades and text preset names. Reusable grades are library `look` items (C8); a project scope library keeps
// a project's own. Projects saved with the old `looks`/`styleKits` fields keep them as unknown fields.

/// The color keys an item, adjustment or look may carry, with their allowed ranges; `lut` is a catalog ID.
public enum ColorGrade {
    public static let ranges: [(key: String, range: ClosedRange<Double>)] = [
        ("exposure", -10...10), ("contrast", 0...4), ("saturation", 0...4), ("lutStrength", 0...1),
    ]

    /// Checks ranges and the LUT reference; other keys round-trip. `path` names the grade in error messages.
    static func validate(_ color: [String: JSONValue], path: String, lutIDs: Set<String>) throws {
        for (key, range) in ranges {
            guard let value = color[key] else { continue }
            guard let number = value.double, number.isFinite, range.contains(number) else {
                throw ProjectError.invalid("\(path).\(key): expected a number in \(range)")
            }
        }
        if let lut = color["lut"], lut != .null, lut.string.map(lutIDs.contains) != true {
            throw ProjectError.invalid("\(path): unknown LUT")
        }
    }
}

/// The text presets the caption renderer draws (`textPreset` on a text item).
public enum TextPreset {
    public static let all = [
        "bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "hook-title", "chapter-card",
    ]
}

/// Shared rules for IDs of library items and catalog entries.
public enum StyleCatalog {
    public static let idPattern = "^[a-z0-9][a-z0-9-]{0,63}$"
}
