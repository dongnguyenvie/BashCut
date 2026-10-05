import Foundation

/// Agent terminals fold a long paste into a placeholder ("[Pasted Content 1801 chars]", "[Pasted text #1 +23 lines]"),
/// which hides the request. The dock writes the context to a file instead and pastes only the request and the file's
/// path, so the input stays short enough to read and edit before sending.
public enum AgentContextFile {
    public static let fileName = "context.md"

    /// Writes `text` to `folder/context.md`, readable by the owner only, and returns its URL.
    @discardableResult
    public static func write(_ text: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent(fileName)
        try Data(text.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// What goes in the agent's input: the request, a line pointing at the context file and the attached frame.
    /// Paths start with `~` to stay short; it ends with a newline so a second paste starts on its own line.
    public static func prompt(request: String, context: URL, image: URL? = nil) -> String {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = short(context)
        var lines = [
            request.isEmpty
                ? "Read the BashCut context in `\(path)`."
                : request + "\n(BashCut context: `\(path)`, read it first.)"
        ]
        if let image { lines.append("Current viewer frame: `\(short(image))`") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func short(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
}
