import AppKit
import BashCutAgent
import BashCutAutomation
import Foundation

/// Claude Code and Codex ask before working in a folder they do not trust, and Claude Code warns once about Bypass
/// Permissions mode; BashCut asks in its own sheet first and records the answer where the CLI reads it, so the CLI's
/// menus never show. When the write does not take, the CLI
/// still asks and the brief waits for it (`AgentScreen.isAsking`).
extension AgentDockModel {
    enum FolderTrustError: LocalizedError {
        case declined(String)
        case bypassDeclined(String)
        case busy
        var errorDescription: String? {
            switch self {
            case .declined(let agent): String(format: String(localized: "%@ was not started: the folder was not allowed."), agent)
            case .bypassDeclined(let agent):
                String(format: String(localized: "%@ was not started: Bypass Permissions mode was not accepted."), agent)
            case .busy: String(localized: "Answer the folder question in BashCut first.")
            }
        }
    }

    func ensureFolderTrust(_ provider: any AgentProvider, folder: URL) async throws {
        guard AgentFolderTrust.asks(provider.id) else { return }
        let trust = AgentFolderTrust(folders: document.currentAgentConfigFolders)
        let needsFolder = !trust.isTrusted(provider.id, folder: folder)
        // BashCut starts Claude Code with --dangerously-skip-permissions, which warns once per config.
        let needsBypass = provider.id == .claude && !trust.acceptsClaudeBypass
        guard needsFolder || needsBypass else { return }
        let allowed = provider.id.rawValue + ":" + AgentFolderTrust.key(folder)
        let bypass = "claude-bypass:" + trust.claudeSettings.path
        let asksFolder = needsFolder && !allowedFolders.contains(allowed)
        let asksBypass = needsBypass && !allowedFolders.contains(bypass)
        if asksFolder || asksBypass {
            // One answer for every project: Claude Code also trusts the folders below a trusted one.
            let projects = settings.defaultProjectsFolder
            let prompt = AgentFolderTrustPrompt(
                agent: provider.title, folder: folder,
                projectsFolder: asksFolder && provider.id == .claude && AgentFolderTrust.parent(projects, covers: folder)
                    ? projects : nil,
                asksFolder: asksFolder, acceptsBypass: asksBypass)
            let answer = try await askFolderTrust(prompt)
            if answer == .notNow {
                let declined = asksFolder
                    ? FolderTrustError.declined(provider.title) : FolderTrustError.bypassDeclined(provider.title)
                document.message = declined.localizedDescription
                throw declined
            }
            if answer == .allowProjectsFolder, let projects = prompt.projectsFolder {
                record(trust, provider, folder: projects)
            }
            if asksFolder { allowedFolders.insert(allowed) }
            if asksBypass { allowedFolders.insert(bypass) }
        }
        // A running CLI may have saved its own copy of the file since; check again right before the launch.
        recordAgain(trust, provider, folder: folder, needsFolder: needsFolder, needsBypass: needsBypass)
    }

    private func recordAgain(
        _ trust: AgentFolderTrust, _ provider: any AgentProvider, folder: URL, needsFolder: Bool, needsBypass: Bool
    ) {
        if needsFolder, !trust.isTrusted(provider.id, folder: folder) { record(trust, provider, folder: folder) }
        if needsFolder, !trust.isTrusted(provider.id, folder: folder) {
            DebugLog.write("agents", "\(provider.id.rawValue) still does not trust \(folder.path); the CLI will ask")
        }
        if needsBypass, !trust.acceptsClaudeBypass {
            do { try trust.acceptClaudeBypass() } catch {
                DebugLog.write("agents", "could not accept Claude bypass mode in \(trust.claudeSettings.path): \(error)")
            }
        }
    }

    private func record(_ trust: AgentFolderTrust, _ provider: any AgentProvider, folder: URL) {
        do { try trust.trust(provider.id, folder: folder) } catch {
            DebugLog.write("agents", "could not record \(provider.id.rawValue) trust for \(folder.path): \(error)")
        }
    }

    /// Shows the question and waits for the user. The New brief sheet closes first (a window shows
    /// one sheet); its brief is sent once the agent starts.
    private func askFolderTrust(_ prompt: AgentFolderTrustPrompt) async throws -> AgentFolderTrustPrompt.Answer {
        guard folderTrustAnswer == nil else {
            throw FolderTrustError.busy
        }
        if document.ui.showAsk {
            document.ui.showAsk = false
            try? await Task.sleep(for: .milliseconds(350))
        }
        NSApp.activate(ignoringOtherApps: true)
        return await withCheckedContinuation { continuation in
            folderTrustAnswer = continuation
            folderTrustPrompt = prompt
        }
    }

    func resolveFolderTrust(_ answer: AgentFolderTrustPrompt.Answer) {
        let continuation = folderTrustAnswer
        folderTrustAnswer = nil
        folderTrustPrompt = nil
        continuation?.resume(returning: answer)
    }
}
