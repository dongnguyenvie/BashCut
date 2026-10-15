import Testing

@testable import BashCutAgent

@Suite struct AgentSetupChecklistTests {
    private typealias Status = AgentKitSetup.Status
    private let found = "/usr/local/bin/agent"

    @Test("Skills: done only when every agent CLI found has the current kit")
    func skillsState() {
        let none = AgentSetupChecklist.skills(kitVersion: "0.4.0", statuses: [
            .claude: Status(executable: nil, installed: false, detail: ""),
            .codex: Status(executable: nil, installed: false, detail: ""),
        ])
        #expect(none == .notApplicable)
        #expect(AgentSetupChecklist.skills(kitVersion: nil, statuses: [
            .claude: Status(executable: found, installed: false, detail: ""),
        ]) == .notApplicable)
        #expect(AgentSetupChecklist.skills(kitVersion: "0.4.0", statuses: [
            .claude: Status(executable: found, installed: true, detail: ""),
            .codex: Status(executable: found, installed: false, detail: ""),
        ]) == .missing)
        #expect(AgentSetupChecklist.skills(kitVersion: "0.4.0", statuses: [
            .claude: Status(executable: found, installed: true, detail: "", outdated: true),
        ]) == .outdated)
        // A CLI that is not on this Mac does not hold the step back.
        #expect(AgentSetupChecklist.skills(kitVersion: "0.4.0", statuses: [
            .claude: Status(executable: found, installed: true, detail: ""),
            .codex: Status(executable: nil, installed: false, detail: ""),
        ]) == .installed(version: "0.4.0"))
    }

    @Test("Tools: done when every default plugin is installed and healthy")
    func toolsState() {
        typealias Plugin = AgentSetupChecklist.ToolPlugin
        #expect(AgentSetupChecklist.tools(nil) == .notApplicable)
        #expect(AgentSetupChecklist.tools([]) == .notApplicable)
        #expect(AgentSetupChecklist.tools([
            Plugin(installed: true, healthy: true), Plugin(installed: false, healthy: false),
            Plugin(installed: false, healthy: false),
        ]) == .missing(installed: 1, of: 3))
        #expect(AgentSetupChecklist.tools([
            Plugin(installed: true, healthy: true), Plugin(installed: true, healthy: false),
        ]) == .needsSetup)
        // Not checked yet is not done.
        #expect(AgentSetupChecklist.tools([Plugin(installed: true, healthy: nil)]) == .needsSetup)
        #expect(AgentSetupChecklist.tools([
            Plugin(installed: true, healthy: true), Plugin(installed: true, healthy: true),
        ]) == .ready)
    }

    @Test("Done and total count only the steps that apply")
    func counts() {
        let fresh = AgentSetupChecklist(skills: .missing, tools: .missing(installed: 0, of: 7))
        #expect(fresh.done == 0)
        #expect(fresh.total == 2)
        #expect(!fresh.isComplete)

        let half = AgentSetupChecklist(skills: .installed(version: "0.4.0"), tools: .needsSetup)
        #expect(half.done == 1)
        #expect(half.total == 2)
        #expect(half.skillsName == "installed")
        #expect(half.toolsName == "needs-setup")

        let noRegistry = AgentSetupChecklist(skills: .outdated, tools: .notApplicable)
        #expect(noRegistry.total == 1)
        #expect(noRegistry.done == 0)

        let finished = AgentSetupChecklist(skills: .installed(version: "0.4.0"), tools: .ready)
        #expect(finished.isComplete)
        #expect(finished.done == 2)

        let nothing = AgentSetupChecklist(skills: .notApplicable, tools: .notApplicable)
        #expect(nothing.total == 0)
        #expect(nothing.isComplete)
    }

    @Test("Later folds the card until a newer kit")
    func foldKey() {
        #expect(AgentSetupChecklist.foldKey(kitVersion: "0.4.0") == "0.4.0")
        #expect(AgentSetupChecklist.foldKey(kitVersion: nil) == "-")
        #expect(AgentSetupChecklist.foldKey(kitVersion: "0.5.0") != AgentSetupChecklist.foldKey(kitVersion: "0.4.0"))
    }

    @Test("The card is about the agent the user picked when its CLI is found, else every CLI found")
    func pickedAgent() {
        let statuses: [AgentKitSetup.Target: Status] = [
            .claude: Status(executable: found, installed: true, detail: "", outdated: true),
            .codex: Status(executable: found, installed: false, detail: ""),
        ]
        // Claude picked: Codex's missing kit neither names the card nor holds the step back.
        let claude = AgentSetupChecklist.statuses(statuses, pickedFrom: [.claude])
        #expect(Array(claude.keys) == [.claude])
        #expect(AgentSetupChecklist.skills(kitVersion: "0.4.0", statuses: claude) == .outdated)
        // A shown Codex tab wins over the default agent.
        #expect(Array(AgentSetupChecklist.statuses(statuses, pickedFrom: [.codex, .claude]).keys) == [.codex])
        // A shell tab is skipped for the default agent.
        #expect(Array(AgentSetupChecklist.statuses(statuses, pickedFrom: [.shell, .claude]).keys) == [.claude])
        // A picked agent whose CLI is not on this Mac falls back to every CLI found.
        let noCodex: [AgentKitSetup.Target: Status] = [
            .claude: Status(executable: found, installed: true, detail: ""),
            .codex: Status(executable: nil, installed: false, detail: ""),
        ]
        #expect(AgentSetupChecklist.statuses(noCodex, pickedFrom: [.codex]) == noCodex)
        #expect(AgentSetupChecklist.statuses(statuses, pickedFrom: []) == statuses)
    }
}
