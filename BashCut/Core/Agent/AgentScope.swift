import BashCutProject
import Foundation

/// A timeline item attached to an agent request with Send to Agent: the scope the request is about. It is a copy
/// taken when attached, so a chip keeps showing the same clip when the selection changes later.
public struct AgentScopeItem: Codable, Hashable, Sendable, Identifiable {
    /// The timeline item's stable ID.
    public var id: String
    /// Its linked sound or picture, which follows its edits.
    public var linked: String?
    /// The layer's ID and name.
    public var track: String
    public var layer: String
    /// The clip's file name, text, or adjustment title.
    public var name: String
    /// Timeline frames `[start, end)` when it was attached.
    public var start: Int
    public var end: Int

    public init(id: String, linked: String? = nil, track: String, layer: String, name: String, start: Int, end: Int) {
        self.id = id
        self.linked = linked
        self.track = track
        self.layer = layer
        self.name = name
        self.start = start
        self.end = end
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(id), "track": .string(track), "layer": .string(layer), "name": .string(name),
            "start": .integer(start), "end": .integer(end),
        ]
        if let linked { fields["linked"] = .string(linked) }
        return .object(fields)
    }
}

/// Builds and words the scope a request carries (#355): which items, and the rule to edit only those.
public enum AgentScope {
    /// The items with these IDs, in timeline order, a linked pair once and as its picture.
    public static func items(_ ids: [String], in project: Project) -> [AgentScopeItem] {
        SelectionEdits.roots(ids, in: project).compactMap { root in
            let picture = root.fields["linkedVideo"]?.string.flatMap { id in
                project.tracks.flatMap(\.items).first { $0.id == id }
            }
            let item = picture ?? root
            guard let track = project.tracks.first(where: { $0.items.contains { $0.id == item.id } }) else { return nil }
            return AgentScopeItem(
                id: item.id, linked: item.linkedItemID, track: track.id, layer: track.name,
                name: name(item, track: track, in: project), start: item.at, end: item.end)
        }
    }

    /// Adds `new` after `current`, skipping items already there (by ID or as a linked partner).
    public static func merge(_ current: [AgentScopeItem], _ new: [AgentScopeItem]) -> [AgentScopeItem] {
        var result = current
        for item in new where !result.contains(where: { $0.id == item.id || $0.linked == item.id || $0.id == item.linked }) {
            result.append(item)
        }
        return result
    }

    /// The chip title: `Clip name · Main · 00:12–00:18`.
    public static func label(_ item: AgentScopeItem, fps: FrameRate) -> String {
        "\(item.name) · \(item.layer) · \(clock(item.start, fps: fps))–\(clock(item.end, fps: fps))"
    }

    /// The scope as the agent reads it, before the request: one line per item with its IDs, then the rule.
    /// Empty when nothing is attached.
    public static func text(_ items: [AgentScopeItem], fps: FrameRate) -> String {
        guard !items.isEmpty else { return "" }
        let lines = items.map { item in
            "- \(item.id)" + (item.linked.map { " (linked \($0))" } ?? "")
                + ": \(item.name), layer \(item.layer), frames \(item.start)-\(item.end) (\(label(item, fps: fps)))"
        }
        return (["[Scope: timeline items this request is about]"] + lines + [rule, "[/Scope]"])
            .joined(separator: "\n")
    }

    /// What the agent may change while a scope is attached.
    public static let rule = "Edit only these items; ask before changing anything else."

    /// `mm:ss`, or `h:mm:ss` past an hour.
    static func clock(_ frame: Int, fps: FrameRate) -> String {
        let seconds = Int(Double(max(0, frame)) / max(fps.value, 1))
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    private static func name(_ item: Item, track: Track, in project: Project) -> String {
        if track.isAdjustment { return item.adjustmentTitle(in: project) }
        if !item.text.isEmpty {
            let text = item.text.replacingOccurrences(of: "\n", with: " ")
            return text.count > 30 ? String(text.prefix(29)) + "…" : text
        }
        if let media = item.mediaID.flatMap({ id in project.media.first { $0.id == id } }) {
            return URL(fileURLWithPath: media.path).lastPathComponent
        }
        return item.id
    }
}
