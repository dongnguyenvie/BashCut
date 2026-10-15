import Foundation

/// BashCut's question before Claude Code or Codex starts in a folder it does not trust yet, asked instead of the
/// CLI's own menu. Only the user answers it.
struct AgentFolderTrustPrompt: Identifiable {
    enum Answer { case allow, allowProjectsFolder, notNow }

    let id = UUID()
    let agent: String
    let folder: URL
    /// BashCut's projects folder, offered (and ticked) so one answer covers every project; nil when trusting it would
    /// not cover `folder`.
    let projectsFolder: URL?
}
