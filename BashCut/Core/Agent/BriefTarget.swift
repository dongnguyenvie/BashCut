import Foundation

/// Where New brief sends its request: an open terminal tab, a chat agent's tab, or an agent it starts first.
public enum BriefTarget: Hashable, Sendable {
    case session(UUID)
    case chat(String)
    case start(AgentProviderID)

    /// An open terminal tab, as the choice sees it.
    public struct Tab: Sendable {
        public let id: UUID
        public let provider: AgentProviderID
        /// A plain shell never gets a brief: it would run the request as commands.
        public let isAgent: Bool
        public init(id: UUID, provider: AgentProviderID, isAgent: Bool) {
            self.id = id
            self.provider = provider
            self.isAgent = isAgent
        }
    }

    /// The target to send to: the user's pick while it still exists, else the chat or agent tab on show (`shown`),
    /// else the newest tab of the default agent, else starting the default agent.
    public static func resolve(
        picked: BriefTarget?, shown: BriefTarget?, tabs: [Tab], chats: [String], defaultAgent: AgentProviderID
    ) -> BriefTarget {
        let agentTabs = tabs.filter(\.isAgent)
        switch picked {
        case .session(let id) where agentTabs.contains(where: { $0.id == id }): return .session(id)
        case .chat(let id) where chats.contains(id): return .chat(id)
        case .start(let provider): return .start(provider)
        default: break
        }
        switch shown {
        case .chat(let id) where chats.contains(id): return .chat(id)
        case .session(let id) where agentTabs.contains(where: { $0.id == id }): return .session(id)
        default: break
        }
        if let tab = agentTabs.last(where: { $0.provider == defaultAgent }) { return .session(tab.id) }
        return .start(defaultAgent)
    }
}

/// The agent the dock starts by default.
public enum AgentDefault {
    /// `chosen` is the agent picked in Settings, nil for "Last used". Falls back to the last used agent, then Claude
    /// Code, then the first agent there is.
    public static func resolve(
        chosen: AgentProviderID?, last: AgentProviderID?, available: [AgentProviderID]
    ) -> AgentProviderID {
        if let chosen, available.contains(chosen) { return chosen }
        if let last, available.contains(last) { return last }
        return available.contains(.claude) ? .claude : available.first ?? .claude
    }
}
