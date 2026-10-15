import Foundation

/// What an agent CLI's screen shows, for sending a request at the right time.
public enum AgentScreen {
    /// Lines of the menus Claude Code and Codex show before their input box (trusting a folder, first-run setup).
    /// A paste and Return there would answer the menu, often "No, exit", and the request would be lost.
    static let questionMarkers = ["enter to confirm", "press enter to continue", "do you trust", "trust this folder"]

    /// Whether the screen asks the user something the request must not answer.
    public static func isAsking(_ screen: String) -> Bool {
        // TUIs move the cursor instead of printing spaces, so words on screen are apart by empty (NUL) cells.
        let words = screen.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        return questionMarkers.contains { words.contains($0) }
    }
}
