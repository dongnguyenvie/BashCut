import Foundation

/// Text layout as data for the agent (`review.layout`, #465): each text item's box as the renderer draws it, its size
/// against the frame and its margins to each edge, next to the zones of the project's platform. No verdicts.
public enum ReviewLayout {
    /// The text items on visible text tracks, or only those on screen at `frame`, or only those that overlap `range`.
    /// With `words` (heard or caption words), each item also says how it sits against the speech (P0-B6).
    public static func json(
        _ project: Project, context: ReviewContext, frame: Int? = nil, range: Range<Int>? = nil,
        words: [ReviewSync.WordSpan]? = nil
    ) -> JSONValue {
        let all = textItems(project, frame: nil)
        let scene = TextFacts.Scene(project: project, context: context, all: all, words: words)
        let shown = textItems(project, frame: frame).filter { _, item in
            range.map { item.at < $0.upperBound && item.end > $0.lowerBound } ?? true
        }
        let rows = shown.map { track, item in
            var row = row(item, track: track, project: project, context: context).object
            row.merge(TextFacts.json(item, track: track, in: scene)) { _, new in new }
            return JSONValue.object(row)
        }
        var result: [String: JSONValue] = [
            "width": .integer(project.width), "height": .integer(project.height),
            "platform": context.targets.layoutPlatform(for: project)?.json ?? .null, "items": .array(rows),
            "density": TextFacts.density(all, project: project), "facesProvider": .bool(false),
        ]
        if let frame {
            result["frame"] = .integer(frame)
            result["pictures"] = TextFacts.pictures(project, at: frame)
        }
        return .object(result)
    }

    /// Non-empty text items on visible text tracks (on screen at `frame` when given), in time order.
    static func textItems(_ project: Project, frame: Int?) -> [(Track, Item)] {
        guard project.width > 0, project.height > 0 else { return [] }
        let tracks = project.tracks.filter { $0.kind == "text" && $0["hidden"] != .bool(true) }
        var items: [(Track, Item)] = []
        for track in tracks {
            for item in track.items where !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let frame, !(item.at <= frame && frame < item.end) { continue }
                items.append((track, item))
            }
        }
        return items.sorted { $0.1.at < $1.1.at }
    }

    static func row(_ item: Item, track: Track, project: Project, context: ReviewContext) -> JSONValue {
        let width = Double(project.width)
        let height = Double(project.height)
        let box = TimelineReview.textBox(item, width: width, height: height, context: context)
        let longest = item.text.components(separatedBy: "\n").map(\.count).max() ?? 0
        // Pixels from the top-left corner, like a frame image.
        let bounds: JSONValue = .object([
            "x": .number(rounded(box.minX)), "y": .number(rounded(height - box.maxY)),
            "width": .number(rounded(box.maxX - box.minX)), "height": .number(rounded(box.maxY - box.minY)),
        ])
        // Distance from each frame edge as a share of that dimension; negative when outside the frame.
        let edges: JSONValue = .object([
            "left": .number(rounded(box.minX / width)), "right": .number(rounded(1 - box.maxX / width)),
            "top": .number(rounded(1 - box.maxY / height)), "bottom": .number(rounded(box.minY / height)),
        ])
        var row: [String: JSONValue] = [
            "id": .string(item.id), "track": .string(track.id), "trackRole": .string(track.role),
            "at": .integer(item.at), "end": .integer(item.end), "text": .string(item.text),
            "lines": .integer(box.lines), "longestLineChars": .integer(longest),
            "fontPixels": .number(rounded(box.points)), "fontShare": .number(rounded(box.points / min(width, height))),
            "bounds": bounds, "edges": edges, "measured": .bool(box.measured),
        ]
        if let preset = item.textPreset { row["preset"] = .string(preset) }
        if item["keyframes"] != nil { row["keyframed"] = .bool(true) }
        return .object(row)
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
