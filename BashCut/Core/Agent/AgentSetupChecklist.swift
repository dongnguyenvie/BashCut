import Foundation

/// The agent dock's two setup steps: the BashCut skills for Claude Code and Codex on this Mac, and the starter plugin
/// bundle (editing tools). A step that does not apply on this Mac (no agent CLI, no plugin registry) is left out of
/// the count.
public struct AgentSetupChecklist: Sendable, Equatable {
    public enum Skills: Sendable, Equatable {
        /// Neither Claude Code nor Codex is on this Mac, or BashCut has no kit.
        case notApplicable
        case missing
        case outdated
        case installed(version: String)
    }

    public enum Tools: Sendable, Equatable {
        /// The registry or its starter bundle is not known yet, or this build takes no user plugins.
        case notApplicable
        /// Some default plugins of the bundle are not installed.
        case missing(installed: Int, of: Int)
        /// Every default plugin is installed, but one still reports a missing dependency or was not checked yet.
        case needsSetup
        case ready
    }

    /// One default plugin of the starter bundle as this Mac has it.
    public struct ToolPlugin: Sendable, Equatable {
        public let installed: Bool
        /// The last health check found it ready, or it has no dependencies to check. nil: not checked yet.
        public let healthy: Bool?

        public init(installed: Bool, healthy: Bool?) {
            self.installed = installed
            self.healthy = healthy
        }
    }

    public let skills: Skills
    public let tools: Tools

    public init(skills: Skills, tools: Tools) {
        self.skills = skills
        self.tools = tools
    }

    /// The skills step from `agent status`: done once every agent CLI found has the current kit.
    public static func skills(
        kitVersion: String?, statuses: [AgentKitSetup.Target: AgentKitSetup.Status]
    ) -> Skills {
        guard let kitVersion else { return .notApplicable }
        let found = statuses.values.filter { $0.executable != nil }
        guard !found.isEmpty else { return .notApplicable }
        if found.contains(where: { !$0.installed }) { return .missing }
        if found.contains(where: \.outdated) { return .outdated }
        return .installed(version: kitVersion)
    }

    /// The tools step from the bundle's default plugins; nil plugins when the bundle is not known.
    public static func tools(_ plugins: [ToolPlugin]?) -> Tools {
        guard let plugins, !plugins.isEmpty else { return .notApplicable }
        let installed = plugins.filter(\.installed).count
        guard installed == plugins.count else { return .missing(installed: installed, of: plugins.count) }
        return plugins.allSatisfy { $0.healthy == true } ? .ready : .needsSetup
    }

    public var skillsDone: Bool { if case .installed = skills { true } else { false } }
    public var toolsDone: Bool { tools == .ready }

    /// Steps that apply on this Mac (0–2).
    public var total: Int { (skills == .notApplicable ? 0 : 1) + (tools == .notApplicable ? 0 : 1) }
    public var done: Int { (skillsDone ? 1 : 0) + (toolsDone ? 1 : 0) }
    public var isComplete: Bool { done == total }

    /// What `ui view` reports.
    public var skillsName: String {
        switch skills {
        case .notApplicable: "not-applicable"
        case .missing: "missing"
        case .outdated: "outdated"
        case .installed: "installed"
        }
    }

    public var toolsName: String {
        switch tools {
        case .notApplicable: "not-applicable"
        case .missing: "missing"
        case .needsSetup: "needs-setup"
        case .ready: "ready"
        }
    }

    /// The statuses the card is about: only the agent the user picked (the first of `picked` that is Claude Code or
    /// Codex and found on this Mac, e.g. the shown tab's agent, then the dock's default), else every CLI found.
    public static func statuses(
        _ statuses: [AgentKitSetup.Target: AgentKitSetup.Status], pickedFrom picked: [AgentProviderID]
    ) -> [AgentKitSetup.Target: AgentKitSetup.Status] {
        for id in picked {
            if let target = AgentKitSetup.Target(rawValue: id.rawValue), let status = statuses[target],
                status.executable != nil
            {
                return [target: status]
            }
        }
        return statuses
    }

    /// Later folds the card into the dock's Setup chip until BashCut has a newer kit; the key it saves.
    public static func foldKey(kitVersion: String?) -> String { kitVersion ?? "-" }
}
