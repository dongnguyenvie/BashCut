import BashCutEngine
import Foundation
import Observation

/// App preferences from Settings, plus the recent-projects list. Each change is written to
/// `UserDefaults` at once under the keys earlier builds used, so existing preferences carry over.
@MainActor @Observable
public final class SettingsModel {
    public static let recentProjectLimit = 8

    /// Folder agents work in and shared media resolves against; nil uses the project folder, or without a project the
    /// projects folder (~/Movies/BashCut), never the home folder.
    public var workspace: URL? {
        didSet {
            if let workspace { defaults.set(workspace.path, forKey: Keys.workspace) } else {
                defaults.removeObject(forKey: Keys.workspace)
            }
        }
    }
    /// Folder New Project and `project create` put new projects in; nil uses `standardProjectsFolder`.
    public var projectsFolder: URL? { didSet { store(projectsFolder, Keys.projectsFolder) } }
    /// Load the agent kit's editing skills in BashCut's Claude and Codex tabs. On by default.
    public var loadAgentKit: Bool { didSet { defaults.set(loadAgentKit, forKey: Keys.loadAgentKit) } }
    /// A kit folder to use instead of the one inside BashCut (a checkout being worked on); nil uses the built-in kit.
    public var agentKitFolder: URL? { didSet { store(agentKitFolder, Keys.agentKitFolder) } }
    /// The kit version whose setup banner the user put off with Later; a newer kit shows it again.
    public var agentKitPromptDismissed: String? {
        didSet { defaults.set(agentKitPromptDismissed, forKey: Keys.agentKitPromptDismissed) }
    }
    /// Claude Code's configuration folder when it is not found by itself (`CLAUDE_CONFIG_DIR`); nil detects it.
    public var claudeConfigFolder: URL? {
        didSet { store(claudeConfigFolder, Keys.claudeConfigFolder) }
    }
    /// Codex's home folder when it is not found by itself (`CODEX_HOME`); nil detects it.
    public var codexHomeFolder: URL? {
        didSet { store(codexHomeFolder, Keys.codexHomeFolder) }
    }
    /// `AgentProviderID` raw value of the agent the dock starts by default.
    public var defaultProviderRaw: String { didSet { defaults.set(defaultProviderRaw, forKey: Keys.defaultAgent) } }
    public var allowAgentEdits: Bool { didSet { defaults.set(allowAgentEdits, forKey: Keys.allowAgentEdits) } }
    /// Agents outside the app (CLI/MCP from any terminal) edit through the 0600 automation token file.
    public var allowExternalAgents: Bool {
        didSet { defaults.set(allowExternalAgents, forKey: Keys.allowExternalAgents) }
    }
    /// Dangerously allow all agent actions: timeline edits, privileged actions (exports, kit setup, library items for
    /// every project, preferences), edits outside an attached scope and plugin action confirmations all run without
    /// asking. Installing and trusting plugins stays with the user. Off by default; only the user can change it.
    public var dangerouslyAllowAgents: Bool {
        didSet { defaults.set(dangerouslyAllowAgents, forKey: Keys.dangerouslyAllowAgents) }
    }
    /// Whether agents may edit: their own switch, or everything allowed.
    public var agentsCanEdit: Bool { dangerouslyAllowAgents || allowAgentEdits }
    /// Whether privileged agent actions run without the approval sheet.
    public var agentActionsAutoApproved: Bool { dangerouslyAllowAgents || autoApprovePrivileged }
    /// What happens when an agent with an attached scope edits outside it (#356): `ask`, `block` or `off`
    /// (`AgentScopeMode`). Like export approval, only the user can change it in Settings.
    public var agentScopeModeRaw: String {
        didSet { defaults.set(agentScopeModeRaw, forKey: Keys.agentScopeMode) }
    }
    /// Gate modes by ID (`G1`…`G5`, P1-D4); a gate not listed asks. Only the user loosens a gate.
    public var workflowGatesRaw: [String: String] {
        didSet { defaults.set(workflowGatesRaw, forKey: Keys.workflowGates) }
    }
    /// The most review rounds an agent runs before it hands the rest to the user (P1-D4).
    public var maxReviewRounds: Int { didSet { defaults.set(maxReviewRounds, forKey: Keys.maxReviewRounds) } }
    /// Run privileged agent commands (exports) without the in-app confirmation sheet. Off by default;
    /// only the user can change it in Settings — no automation command exists for it.
    public var autoApprovePrivileged: Bool {
        didSet { defaults.set(autoApprovePrivileged, forKey: Keys.autoApprovePrivileged) }
    }
    /// Deliver editor events to plugin hooks. On by default; each plugin also has its own hooks switch.
    public var runPluginHooks: Bool { didSet { defaults.set(runPluginHooks, forKey: Keys.runPluginHooks) } }
    /// Apply edits proposed by plugin hooks at once instead of asking. Off by default; like export approval,
    /// only the user can change it in Settings.
    public var autoApplyPluginHookEdits: Bool {
        didSet { defaults.set(autoApplyPluginHookEdits, forKey: Keys.autoApplyPluginHookEdits) }
    }
    /// Look for plugin updates in the registry once a day when a project opens. Only marks them; installing
    /// stays a user decision.
    public var checkPluginUpdatesDaily: Bool {
        didSet { defaults.set(checkPluginUpdatesDaily, forKey: Keys.checkPluginUpdatesDaily) }
    }
    /// Look for a newer BashCut release once a day when a project opens. Only tells; updating stays a user decision.
    public var checkAppUpdatesDaily: Bool {
        didSet { defaults.set(checkAppUpdatesDaily, forKey: Keys.checkAppUpdatesDaily) }
    }
    /// The release the user skipped (Skip This Version): no prompt or ☰ dot for it; a newer release shows again.
    public var appUpdateDismissed: String? {
        didSet { defaults.set(appUpdateDismissed, forKey: Keys.appUpdateDismissed) }
    }
    /// Remind Me Later: the update prompt does not open by itself before this time. The ☰ dot stays.
    public var appUpdateRemindAfter: Date? {
        didSet { defaults.set(appUpdateRemindAfter, forKey: Keys.appUpdateRemindAfter) }
    }
    /// `ExportPreset` raw value the Export sheet starts with.
    public var defaultExportPresetRaw: String {
        didSet { defaults.set(defaultExportPresetRaw, forKey: Keys.defaultExportPreset) }
    }
    /// "system", "en" or "vi"; applies after a restart.
    public var interfaceLanguage: String {
        didSet {
            defaults.set(interfaceLanguage, forKey: Keys.interfaceLanguage)
            if interfaceLanguage == "system" {
                defaults.removeObject(forKey: Keys.appleLanguages)
            } else {
                defaults.set([interfaceLanguage], forKey: Keys.appleLanguages)
            }
        }
    }
    /// Most recent first, at most `recentProjectLimit`.
    public private(set) var recentProjects: [URL]

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let workspace = "agentWorkspace"
        static let workflowGates = "workflowGates"
        static let maxReviewRounds = "maxReviewRounds"
        static let projectsFolder = "projectsFolder"
        static let defaultAgent = "defaultAgent"
        static let loadAgentKit = "loadAgentKit"
        static let agentKitFolder = "agentKitFolder"
        static let agentKitPromptDismissed = "agentKitPromptDismissed"
        static let claudeConfigFolder = "claudeConfigFolder"
        static let codexHomeFolder = "codexHomeFolder"
        static let allowAgentEdits = "allowAgentEdits"
        static let allowExternalAgents = "allowExternalAgents"
        static let autoApprovePrivileged = "autoApprovePrivileged"
        static let agentScopeMode = "agentScopeMode"
        static let dangerouslyAllowAgents = "dangerouslyAllowAgents"
        static let defaultExportPreset = "defaultExportPreset"
        static let runPluginHooks = "runPluginHooks"
        static let autoApplyPluginHookEdits = "autoApplyPluginHookEdits"
        static let checkPluginUpdatesDaily = "checkPluginUpdatesDaily"
        static let checkAppUpdatesDaily = "checkAppUpdatesDaily"
        static let appUpdateDismissed = "appUpdateDismissed"
        static let appUpdateRemindAfter = "appUpdateRemindAfter"
        static let interfaceLanguage = "interfaceLanguage"
        static let appleLanguages = "AppleLanguages"
        static let recentProjects = "recentProjectPaths"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workspace = defaults.string(forKey: Keys.workspace).map { URL(fileURLWithPath: $0) }
        projectsFolder = defaults.string(forKey: Keys.projectsFolder).map { URL(fileURLWithPath: $0) }
        defaultProviderRaw = defaults.string(forKey: Keys.defaultAgent) ?? "codex"
        loadAgentKit = defaults.object(forKey: Keys.loadAgentKit) as? Bool ?? true
        agentKitFolder = defaults.string(forKey: Keys.agentKitFolder).map { URL(fileURLWithPath: $0) }
        agentKitPromptDismissed = defaults.string(forKey: Keys.agentKitPromptDismissed)
        claudeConfigFolder = defaults.string(forKey: Keys.claudeConfigFolder).map { URL(fileURLWithPath: $0) }
        codexHomeFolder = defaults.string(forKey: Keys.codexHomeFolder).map { URL(fileURLWithPath: $0) }
        allowAgentEdits = defaults.object(forKey: Keys.allowAgentEdits) as? Bool ?? true
        allowExternalAgents = defaults.object(forKey: Keys.allowExternalAgents) as? Bool ?? true
        autoApprovePrivileged = defaults.bool(forKey: Keys.autoApprovePrivileged)
        agentScopeModeRaw = defaults.string(forKey: Keys.agentScopeMode) ?? "ask"
        workflowGatesRaw = defaults.dictionary(forKey: Keys.workflowGates) as? [String: String] ?? [:]
        maxReviewRounds = (defaults.object(forKey: Keys.maxReviewRounds) as? Int).map {
            min(max($0, WorkflowGate.roundLimits.lowerBound), WorkflowGate.roundLimits.upperBound)
        } ?? 3
        dangerouslyAllowAgents = defaults.object(forKey: Keys.dangerouslyAllowAgents) as? Bool ?? true
        runPluginHooks = defaults.object(forKey: Keys.runPluginHooks) as? Bool ?? true
        autoApplyPluginHookEdits = defaults.bool(forKey: Keys.autoApplyPluginHookEdits)
        checkPluginUpdatesDaily = defaults.object(forKey: Keys.checkPluginUpdatesDaily) as? Bool ?? true
        checkAppUpdatesDaily = defaults.object(forKey: Keys.checkAppUpdatesDaily) as? Bool ?? true
        appUpdateDismissed = defaults.string(forKey: Keys.appUpdateDismissed)
        appUpdateRemindAfter = defaults.object(forKey: Keys.appUpdateRemindAfter) as? Date
        defaultExportPresetRaw = defaults.string(forKey: Keys.defaultExportPreset) ?? ExportPreset.tiktok.rawValue
        interfaceLanguage = defaults.string(forKey: Keys.interfaceLanguage) ?? "system"
        recentProjects = defaults.stringArray(forKey: Keys.recentProjects)?.map { URL(fileURLWithPath: $0) } ?? []
    }

    /// ~/Movies/BashCut: visible in Finder and, unlike Desktop or Documents, not behind a macOS privacy prompt.
    /// Sandboxed builds reach it through the Movies folder entitlement.
    public static var standardProjectsFolder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true)
        return movies.appendingPathComponent("BashCut", isDirectory: true)
    }

    /// Where a new project goes when no other folder is chosen.
    public var defaultProjectsFolder: URL { projectsFolder ?? Self.standardProjectsFolder }

    /// Remembers the folder a project was just created in as the next default; the standard folder clears it.
    public func rememberProjectsFolder(_ url: URL) {
        let folder = url.standardizedFileURL
        projectsFolder = folder == Self.standardProjectsFolder.standardizedFileURL ? nil : folder
    }

    /// The export preset chosen in Settings, or nil when the user never picked one.
    public var savedExportPreset: ExportPreset? {
        defaults.string(forKey: Keys.defaultExportPreset).flatMap(ExportPreset.init(rawValue:))
    }

    /// Moves `url` to the top of the recent projects.
    public func rememberRecentProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentProjects.removeAll { $0.standardizedFileURL == normalized }
        recentProjects.insert(normalized, at: 0)
        if recentProjects.count > Self.recentProjectLimit { recentProjects.removeLast(recentProjects.count - Self.recentProjectLimit) }
        saveRecentProjects()
    }

    public func forgetRecentProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentProjects.removeAll { $0.standardizedFileURL == normalized }
        saveRecentProjects()
    }

    public func clearRecentProjects() {
        recentProjects.removeAll()
        defaults.removeObject(forKey: Keys.recentProjects)
    }

    private func store(_ url: URL?, _ key: String) {
        if let url { defaults.set(url.path, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func saveRecentProjects() {
        defaults.set(recentProjects.map(\.path), forKey: Keys.recentProjects)
    }
}
