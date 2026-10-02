import BashCutEngine
import Foundation
import Observation

/// App preferences from Settings, plus the recent-projects list. Each change is written to
/// `UserDefaults` at once under the keys earlier builds used, so existing preferences carry over.
@MainActor @Observable
public final class SettingsModel {
    public static let recentProjectLimit = 8

    /// Folder agents work in and shared media resolves against; nil uses the project folder.
    public var workspace: URL? {
        didSet {
            if let workspace { defaults.set(workspace.path, forKey: Keys.workspace) } else {
                defaults.removeObject(forKey: Keys.workspace)
            }
        }
    }
    /// `AgentProviderID` raw value of the agent the dock starts by default.
    public var defaultProviderRaw: String { didSet { defaults.set(defaultProviderRaw, forKey: Keys.defaultAgent) } }
    public var allowAgentEdits: Bool { didSet { defaults.set(allowAgentEdits, forKey: Keys.allowAgentEdits) } }
    /// Agents outside the app (CLI/MCP from any terminal) edit through the 0600 automation token file.
    public var allowExternalAgents: Bool {
        didSet { defaults.set(allowExternalAgents, forKey: Keys.allowExternalAgents) }
    }
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
        static let defaultAgent = "defaultAgent"
        static let allowAgentEdits = "allowAgentEdits"
        static let allowExternalAgents = "allowExternalAgents"
        static let autoApprovePrivileged = "autoApprovePrivileged"
        static let defaultExportPreset = "defaultExportPreset"
        static let runPluginHooks = "runPluginHooks"
        static let autoApplyPluginHookEdits = "autoApplyPluginHookEdits"
        static let interfaceLanguage = "interfaceLanguage"
        static let appleLanguages = "AppleLanguages"
        static let recentProjects = "recentProjectPaths"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workspace = defaults.string(forKey: Keys.workspace).map { URL(fileURLWithPath: $0) }
        defaultProviderRaw = defaults.string(forKey: Keys.defaultAgent) ?? "codex"
        allowAgentEdits = defaults.object(forKey: Keys.allowAgentEdits) as? Bool ?? true
        allowExternalAgents = defaults.object(forKey: Keys.allowExternalAgents) as? Bool ?? true
        autoApprovePrivileged = defaults.bool(forKey: Keys.autoApprovePrivileged)
        runPluginHooks = defaults.object(forKey: Keys.runPluginHooks) as? Bool ?? true
        autoApplyPluginHookEdits = defaults.bool(forKey: Keys.autoApplyPluginHookEdits)
        defaultExportPresetRaw = defaults.string(forKey: Keys.defaultExportPreset) ?? ExportPreset.tiktok.rawValue
        interfaceLanguage = defaults.string(forKey: Keys.interfaceLanguage) ?? "system"
        recentProjects = defaults.stringArray(forKey: Keys.recentProjects)?.map { URL(fileURLWithPath: $0) } ?? []
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

    private func saveRecentProjects() {
        defaults.set(recentProjects.map(\.path), forKey: Keys.recentProjects)
    }
}
