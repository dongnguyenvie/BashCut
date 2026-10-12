import BashCutProject
import Foundation

/// A mark a plugin draws on the timeline or the viewer (#407, host feature `overlays`). Overlays are data: the plugin
/// sends the whole set and replaces it when something changes; BashCut draws them without asking the plugin again.
///
/// - `range`: frames `start..<end` tinted on the timeline (one layer with `track`, else every layer), label on the ruler.
/// - `marker`: a line at frame `start` with a flag on the ruler.
/// - `region`: a rectangle on the viewer (`rect`, 0–1 of the picture), shown while the playhead is in `start..<end`
///   (always when both are left out).
public struct PluginOverlay: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case range, marker, region }

    public struct Rect: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    public let id: String
    public let kind: Kind
    public let start: Int?
    public let end: Int?
    public let track: String?
    public let rect: Rect?
    public let label: String?
    /// A named colour (`accent`, `green`, `orange`, `red`, `purple`, `secondary`) or `#RRGGBB`.
    public let color: String?
    /// `region`: `outline` (default, a dashed frame) or `fill` (a tint).
    public let style: String?

    public static let maximumPerPlugin = 500
    public static let maximumLabel = 80
    public static let colors: Set<String> = ["accent", "green", "orange", "red", "purple", "secondary"]

    /// Whether a region shows at `frame`.
    public func shows(at frame: Int) -> Bool {
        guard kind == .region else { return true }
        return (start.map { frame >= $0 } ?? true) && (end.map { frame < $0 } ?? true)
    }

    /// The frames the overlay covers on the timeline (`marker`: its frame), nil for a region.
    public var frames: Range<Int>? {
        switch kind {
        case .range: guard let start, let end else { return nil }; return start..<end
        case .marker: guard let start else { return nil }; return start..<(start + 1)
        case .region: return nil
        }
    }

    /// Reads a plugin's overlay set (`[{"id", "kind", …}]`); throws on the first bad overlay, so a plugin learns at once.
    public static func parse(_ value: JSONValue) throws -> [PluginOverlay] {
        guard case .array(let items) = value else { throw PluginError.invalid("overlays must be an array") }
        guard items.count <= maximumPerPlugin else {
            throw PluginError.invalid("A plugin draws at most \(maximumPerPlugin) overlays")
        }
        var ids = Set<String>()
        return try items.map { item in
            let overlay = try PluginOverlay(item.object)
            guard ids.insert(overlay.id).inserted else { throw PluginError.invalid("Overlay id \(overlay.id) is used twice") }
            return overlay
        }
    }

    init(_ fields: [String: JSONValue]) throws {
        guard let id = fields["id"]?.string, PluginIdentifier.isKey(id) else {
            throw PluginError.invalid("Each overlay needs a short id")
        }
        guard let kind = fields["kind"]?.string.flatMap(Kind.init(rawValue:)) else {
            throw PluginError.invalid("Overlay \(id) kind must be range, marker or region")
        }
        func frame(_ key: String) throws -> Int? {
            guard let value = fields[key], value != .null else { return nil }
            guard let number = value.int, number >= 0 else {
                throw PluginError.invalid("Overlay \(id) \(key) must be a frame (an integer ≥ 0)")
            }
            return number
        }
        self.id = id
        self.kind = kind
        start = try frame("start")
        end = try frame("end")
        track = fields["track"]?.string
        label = fields["label"]?.string.map { String($0.prefix(Self.maximumLabel)) }
        color = fields["color"]?.string
        style = fields["style"]?.string
        try Self.checkLook(id: id, color: color, style: style)
        rect = try Self.place(kind, id: id, start: start, end: end, rect: fields["rect"]?.object)
    }

    private static func checkLook(id: String, color: String?, style: String?) throws {
        if let color, !colors.contains(color), PluginViewColor.normalized(color) == nil {
            throw PluginError.invalid("Overlay \(id) color must be a named colour or #RRGGBB")
        }
        if let style, !["outline", "fill"].contains(style) {
            throw PluginError.invalid("Overlay \(id) style must be outline or fill")
        }
    }

    /// Checks the frames a kind needs and returns a region's rectangle.
    private static func place(
        _ kind: Kind, id: String, start: Int?, end: Int?, rect box: [String: JSONValue]?
    ) throws -> Rect? {
        switch kind {
        case .range:
            guard let start, let end, end > start else { throw PluginError.invalid("Range overlay \(id) needs start < end") }
            return nil
        case .marker:
            guard start != nil else { throw PluginError.invalid("Marker overlay \(id) needs start") }
            return nil
        case .region:
            let box = box ?? [:]
            guard let x = box["x"]?.double, let y = box["y"]?.double, let width = box["width"]?.double,
                let height = box["height"]?.double, x >= 0, y >= 0, width > 0, height > 0, x + width <= 1.000_001,
                y + height <= 1.000_001
            else {
                throw PluginError.invalid("Region overlay \(id) needs rect {x, y, width, height} inside 0–1 of the picture")
            }
            if let start, let end, end <= start { throw PluginError.invalid("Region overlay \(id) needs start < end") }
            return Rect(x: x, y: y, width: width, height: height)
        }
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id), "kind": .string(kind.rawValue)]
        if let start { fields["start"] = .integer(start) }
        if let end { fields["end"] = .integer(end) }
        if let track { fields["track"] = .string(track) }
        if let rect {
            fields["rect"] = .object([
                "x": .number(rect.x), "y": .number(rect.y), "width": .number(rect.width), "height": .number(rect.height),
            ])
        }
        if let label { fields["label"] = .string(label) }
        if let color { fields["color"] = .string(color) }
        if let style { fields["style"] = .string(style) }
        return .object(fields)
    }
}

/// Every plugin's overlays, ordered for drawing: the timeline ones sorted by start frame so a scroll or a redraw of a
/// part of the timeline finds its overlays by binary search, and the regions apart.
public struct PluginOverlayIndex: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let plugin: String
        public let overlay: PluginOverlay
    }

    /// Ranges and markers by start frame.
    public let timeline: [Entry]
    public let regions: [Entry]
    /// The longest range, so a search can start early enough to find ranges that began before the visible part.
    private let longest: Int

    public init(_ sets: [String: [PluginOverlay]]) {
        let entries = sets.sorted { $0.key < $1.key }.flatMap { plugin, overlays in
            overlays.map { Entry(plugin: plugin, overlay: $0) }
        }
        timeline = entries.filter { $0.overlay.frames != nil }.sorted {
            ($0.overlay.frames?.lowerBound ?? 0) < ($1.overlay.frames?.lowerBound ?? 0)
        }
        regions = entries.filter { $0.overlay.kind == .region }
        longest = timeline.map { $0.overlay.frames?.count ?? 0 }.max() ?? 0
    }

    public var isEmpty: Bool { timeline.isEmpty && regions.isEmpty }

    /// Ranges and markers that touch `frames`.
    public func timeline(in frames: Range<Int>) -> [Entry] {
        let from = frames.lowerBound - longest
        var low = 0, high = timeline.count
        while low < high {
            let middle = (low + high) / 2
            if (timeline[middle].overlay.frames?.lowerBound ?? 0) < from { low = middle + 1 } else { high = middle }
        }
        var upper = low
        while upper < timeline.count, (timeline[upper].overlay.frames?.lowerBound ?? 0) < frames.upperBound { upper += 1 }
        return timeline[low..<upper].filter { $0.overlay.frames?.overlaps(frames) == true }
    }

    /// Regions shown at `frame`.
    public func regions(at frame: Int) -> [Entry] { regions.filter { $0.overlay.shows(at: frame) } }
}
