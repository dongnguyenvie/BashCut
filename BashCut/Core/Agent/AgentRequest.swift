import Foundation

/// What BashCut pastes in an agent terminal for a request. Only the request (and an attached frame) goes in: agent
/// CLIs fold a long paste into a placeholder ("[Pasted Content 1801 chars]") that hides it, and the agents already
/// have BashCut's instructions and read the live selection and playhead with `context get`.
public enum AgentRequest {
    /// The request, then the attached frame's path (with `~`); it ends with a newline so a second paste starts on
    /// its own line. Empty when there is nothing to send.
    /// An attached scope (`AgentScope.text`) goes first, so the request typed after it reads in order.
    public static func paste(_ request: String, image: URL? = nil, scope: String = "") -> String {
        var lines = [scope, request.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        if let image { lines.append("Current viewer frame: `\((image.path as NSString).abbreviatingWithTildeInPath)`") }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}
