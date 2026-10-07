import BashCutDocument
import BashCutEngine
import Foundation
import Testing

@MainActor
struct SettingsModelTests {
    private let suite = "bashcut-settings-tests-" + UUID().uuidString

    private func defaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Defaults match earlier builds and every change is stored under the old keys")
    func persistence() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        #expect(settings.workspace == nil)
        #expect(settings.defaultProviderRaw == "codex")
        #expect(settings.allowAgentEdits && settings.allowExternalAgents && !settings.autoApprovePrivileged)
        #expect(settings.defaultExportPresetRaw == "tiktok")
        #expect(settings.savedExportPreset == nil)
        #expect(settings.interfaceLanguage == "system")

        settings.workspace = URL(fileURLWithPath: "/tmp/workspace")
        settings.defaultProviderRaw = "claude"
        settings.allowAgentEdits = false
        settings.autoApprovePrivileged = true
        settings.defaultExportPresetRaw = ExportPreset.youtube1080.rawValue
        settings.interfaceLanguage = "vi"
        #expect(defaults.string(forKey: "agentWorkspace") == "/tmp/workspace")
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["vi"])
        #expect(settings.savedExportPreset == .youtube1080)

        let reloaded = SettingsModel(defaults: defaults)
        #expect(reloaded.workspace?.path == "/tmp/workspace")
        #expect(reloaded.defaultProviderRaw == "claude")
        #expect(!reloaded.allowAgentEdits && reloaded.autoApprovePrivileged)
        #expect(reloaded.interfaceLanguage == "vi")

        reloaded.interfaceLanguage = "system"
        // Reads fall back to the global domain, so look at the suite itself.
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        reloaded.workspace = nil
        #expect(defaults.string(forKey: "agentWorkspace") == nil)
    }

    @Test("Dangerously allow all agent actions is on by default, overrides the agent switches and is stored")
    func allowAllAgents() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        #expect(settings.dangerouslyAllowAgents && settings.agentScopeModeRaw == "ask")
        settings.allowAgentEdits = false
        #expect(settings.agentsCanEdit && settings.agentActionsAutoApproved)
        // The switches underneath keep their own values for when it is turned off.
        #expect(!settings.allowAgentEdits && !settings.autoApprovePrivileged)

        settings.dangerouslyAllowAgents = false
        #expect(!settings.agentsCanEdit && !settings.agentActionsAutoApproved)
        #expect(!SettingsModel(defaults: defaults).dangerouslyAllowAgents)

        settings.dangerouslyAllowAgents = true
        #expect(SettingsModel(defaults: defaults).dangerouslyAllowAgents)
    }

    @Test("New projects go to ~/Movies/BashCut until another folder is remembered")
    func projectsFolder() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        let standard = SettingsModel.standardProjectsFolder
        #expect(standard.lastPathComponent == "BashCut")
        #expect(standard.deletingLastPathComponent().lastPathComponent == "Movies")
        #expect(settings.projectsFolder == nil && settings.defaultProjectsFolder == standard)

        settings.rememberProjectsFolder(URL(fileURLWithPath: "/tmp/films/./cuts"))
        #expect(defaults.string(forKey: "projectsFolder") == "/tmp/films/cuts")
        #expect(SettingsModel(defaults: defaults).defaultProjectsFolder.path == "/tmp/films/cuts")

        settings.rememberProjectsFolder(standard)
        #expect(settings.projectsFolder == nil)
        #expect(defaults.string(forKey: "projectsFolder") == nil)
    }

    @Test("Recent projects keep the newest first, without duplicates, up to the limit")
    func recentProjects() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        for index in 0..<10 { settings.rememberRecentProject(URL(fileURLWithPath: "/p/\(index)/project.bashcut.json")) }
        #expect(settings.recentProjects.count == SettingsModel.recentProjectLimit)
        #expect(settings.recentProjects.first?.path == "/p/9/project.bashcut.json")
        settings.rememberRecentProject(URL(fileURLWithPath: "/p/5/./project.bashcut.json"))
        #expect(settings.recentProjects.first?.path == "/p/5/project.bashcut.json")
        #expect(settings.recentProjects.count == SettingsModel.recentProjectLimit)
        settings.forgetRecentProject(URL(fileURLWithPath: "/p/5/project.bashcut.json"))
        #expect(SettingsModel(defaults: defaults).recentProjects.count == SettingsModel.recentProjectLimit - 1)
        settings.clearRecentProjects()
        #expect(SettingsModel(defaults: defaults).recentProjects.isEmpty)
    }

    @Test("Every workflow gate asks until the user changes it; modes and the round limit are stored (P1-D4)")
    func workflowGates() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        #expect(WorkflowGate.allCases.allSatisfy { settings.gateMode($0) == .ask })
        #expect(settings.maxReviewRounds == 3)
        settings.setGateMode(.roughCut, .skip)
        settings.setGateMode(.draft, .notify)
        settings.maxReviewRounds = 2
        let reloaded = SettingsModel(defaults: defaults)
        #expect(reloaded.gateMode(.roughCut) == .skip && reloaded.gateMode(.draft) == .notify && reloaded.gateMode(.brief) == .ask)
        #expect(reloaded.maxReviewRounds == 2)
        #expect(WorkflowGate(id: "g3") == .roughCut && WorkflowGate(id: "script") == .script && WorkflowGate(id: "G9") == nil)
        let gates = reloaded.workflowJSON.object["gates"]?.array.map(\.object) ?? []
        #expect(gates.first { $0["id"] == .string("G3") }?["mode"] == .string("skip"))
    }
}
