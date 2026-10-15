import Foundation

/// BashCut's question before Claude Code or Codex starts in a folder it does not trust yet, or before Claude Code
/// first runs in Bypass Permissions mode, asked instead of the CLI's own menus. Only the user answers it.
struct AgentFolderTrustPrompt: Identifiable {
    enum Answer { case allow, allowProjectsFolder, notNow }

    let id = UUID()
    let agent: String
    let folder: URL
    /// BashCut's projects folder, offered (and ticked) so one answer covers every project; nil when trusting it would
    /// not cover `folder`.
    let projectsFolder: URL?
    /// Whether the folder is asked about; false when only Bypass Permissions mode is.
    var asksFolder = true
    /// Whether Allow also accepts Claude Code's Bypass Permissions mode, once for every project.
    var acceptsBypass = false
}
