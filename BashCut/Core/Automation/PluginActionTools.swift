import BashCutProject
import Foundation

/// One MCP tool per installed plugin action, so agents see plugin features next to the built-in commands. The
/// bridge lists them from `plugins.actions` each time tools are listed and runs them through `plugins.run`.
/// At most `budget` are listed (#98): with hundreds of plugins one tool per action would crowd out the built-in
/// tools. Every action, listed or not, stays reachable through `plugins actions` and `plugins run`.
public enum PluginActionTools {
    public static let prefix = "bashcut_action_"
    public static let budget = 40

    public struct Tool: Sendable, Equatable {
        public let name: String
        public let actionID: String
        public let description: String
        public let inputSchema: JSONValue
    }

    /// Tools for the `plugins.actions` result. MCP tool names allow `[A-Za-z0-9_-]` and 64 characters; longer
    /// names keep a stable hash suffix.
    public static func tools(from actions: JSONValue) -> [Tool] {
        (actions.array ?? []).compactMap { action -> Tool? in
            let fields = action.object
            guard let id = fields["id"]?.string else { return nil }
            let title = fields["title"]?.string ?? id
            let plugin = fields["plugin"]?.string ?? ""
            var description = "\(title) (plugin \(plugin), action \(id))."
            if let when = fields["when"]?.string { description += " Needs: \(when)." }
            if fields["enabled"] == .bool(false) { description += " Not available with the current selection." }
            description += " Acts on the current selection (bashcut_ui_select first); returns a job ID for "
                + "bashcut_jobs_status. The edit is one undo step."
            return Tool(name: name(for: id), actionID: id, description: description,
                        inputSchema: fields["params"] ?? .object(["type": .string("object")]))
        }
    }

    /// The tools to list: actions available now first, then the most recently run, then catalog order.
    public static func listed(from actions: JSONValue, budget: Int = budget) -> [Tool] {
        let all = tools(from: actions)
        guard all.count > budget else { return all }
        let fields = Dictionary((actions.array ?? []).compactMap { action in
            action.object["id"]?.string.map { ($0, action.object) }
        }, uniquingKeysWith: { first, _ in first })
        func rank(_ tool: Tool) -> (Bool, String) {
            let action = fields[tool.actionID] ?? [:]
            return (action["enabled"] != .bool(false), action["lastRun"]?.string ?? "")
        }
        let ranked = all.enumerated().sorted { lhs, rhs in
            let (left, right) = (rank(lhs.element), rank(rhs.element))
            if left.0 != right.0 { return left.0 }
            if left.1 != right.1 { return left.1 > right.1 }
            return lhs.offset < rhs.offset
        }
        return ranked.prefix(budget).map(\.element)
    }

    /// Whether `plugins actions QUERY` keeps an action: any of its texts contains the query, ignoring case and
    /// accents. An empty query keeps everything.
    public static func matches(_ query: String?, _ texts: [String]) -> Bool {
        let query = query?.trimmingCharacters(in: .whitespaces) ?? ""
        return query.isEmpty || texts.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    public static func name(for actionID: String) -> String {
        let safe = String(actionID.map { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" ? $0 : "_" })
        let full = prefix + safe
        guard full.count > 64 else { return full }
        var hash: UInt32 = 2_166_136_261
        for byte in actionID.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(full.prefix(55)) + "_" + String(format: "%08x", hash)
    }
}
