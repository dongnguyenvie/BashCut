import Foundation

/// Per-line looks of a text item (text phase 2, two fonts in one title): `textStyle.lines`, a list in reading order
/// whose entries (an object, or null for a line that keeps the block's look) override the block for that line:
/// `font` (a PostScript name, which picks the family and the weight), `scale` (× the block's font size, after the
/// emphasis scale), `fill` and `stroke` (`#RRGGBB`). Lines past the list keep the block's look. Optional and additive:
/// a text item without it draws as before.
public enum TextLineStyles {
    public static let keys = ["font", "scale", "fill", "stroke"]
    public static let scaleRange = 0.2...5.0
    public static let maximumLines = 50

    /// The overrides of line `index` (from the top), or nil when it has none.
    public static func style(_ textStyle: [String: JSONValue], line index: Int) -> [String: JSONValue]? {
        guard case .array(let lines)? = textStyle["lines"], lines.indices.contains(index),
            case .object(let fields) = lines[index], !fields.isEmpty
        else { return nil }
        return fields
    }

    /// The scale of line `index`, clamped like the renderer; 1 without one.
    public static func scale(_ textStyle: [String: JSONValue], line index: Int) -> Double {
        guard let value = style(textStyle, line: index)?["scale"]?.double else { return 1 }
        return min(scaleRange.upperBound, max(scaleRange.lowerBound, value))
    }

    /// The line index `line` names in a block of `count` lines (negative counts from the bottom), or nil outside it.
    public static func index(_ line: Int, count: Int) -> Int? {
        let index = line < 0 ? count + line : line
        return (0..<max(0, count)).contains(index) ? index : nil
    }

    /// `textStyle` with line `index`'s overrides merged with `patch` (null removes a field); `clear` drops the line's
    /// overrides. Trailing lines without overrides are trimmed and an empty list is removed.
    public static func setting(
        _ textStyle: [String: JSONValue], line index: Int, patch: [String: JSONValue], clear: Bool = false
    ) throws -> [String: JSONValue] {
        guard (0..<maximumLines).contains(index) else {
            throw ProjectError.invalid("line must be one of the text's first \(maximumLines) lines")
        }
        var lines = textStyle["lines"]?.array ?? []
        while lines.count <= index { lines.append(.null) }
        var fields = clear ? [:] : lines[index].object
        for (key, value) in patch {
            guard keys.contains(key) else {
                throw ProjectError.invalid("textStyle.lines: unknown field \(key); use \(keys.joined(separator: ", "))")
            }
            fields[key] = value == .null ? nil : value
        }
        lines[index] = fields.isEmpty ? .null : .object(fields)
        while lines.last == .null { lines.removeLast() }
        var result = textStyle
        result["lines"] = lines.isEmpty ? nil : .array(lines)
        try validate(result["lines"], path: "textStyle.lines")
        return result
    }

    /// Checks a `textStyle.lines` value: up to `maximumLines` entries, each null or an object of known fields.
    public static func validate(_ value: JSONValue?, path: String) throws {
        guard let value, value != .null else { return }
        guard case .array(let lines) = value, lines.count <= maximumLines else {
            throw ProjectError.invalid("\(path): expected a list of up to \(maximumLines) line styles")
        }
        for (index, line) in lines.enumerated() {
            if line == .null { continue }
            guard case .object(let fields) = line else {
                throw ProjectError.invalid("\(path)[\(index)]: expected an object or null")
            }
            for (key, field) in fields {
                guard keys.contains(key) else {
                    throw ProjectError.invalid("\(path)[\(index)].\(key): unknown; use \(keys.joined(separator: ", "))")
                }
                if let expected = mismatch(key, field) {
                    throw ProjectError.invalid("\(path)[\(index)].\(key): expected \(expected)")
                }
            }
        }
    }

    /// What a line style field should have been, or nil when it fits.
    static func mismatch(_ key: String, _ value: JSONValue) -> String? {
        switch key {
        case "font": (value.string?.count).map { (1...128).contains($0) } == true ? nil : "a font name"
        case "scale": value.double.map { $0.isFinite && scaleRange.contains($0) } == true ? nil : "a number in \(scaleRange)"
        default: value.string.map(ItemProperty.Rule.isColor) == true ? nil : "a colour #RRGGBB"
        }
    }
}
