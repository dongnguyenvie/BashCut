import BashCutProject
import Foundation

/// One MCP tool per installed plugin action, so agents see plugin features next to the built-in commands. The
/// bridge lists them from `plugins.actions` each time tools are listed and runs them through `plugins.run`.
public enum PluginActionTools {
    public static let prefix = "bashcut_action_"

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

    public static func name(for actionID: String) -> String {
        let safe = String(actionID.map { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" ? $0 : "_" })
        let full = prefix + safe
        guard full.count > 64 else { return full }
        var hash: UInt32 = 2_166_136_261
        for byte in actionID.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(full.prefix(55)) + "_" + String(format: "%08x", hash)
    }
}
