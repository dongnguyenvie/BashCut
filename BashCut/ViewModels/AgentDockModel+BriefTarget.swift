import BashCutAgent
import Foundation

/// An entry in the New brief's "To" menu.
struct BriefTargetChoice: Identifiable {
    let target: BriefTarget
    let title: String
    let icon: String
    var id: BriefTarget { target }
}

extension AgentDockModel {
    /// Where New brief sends: the user's pick in the sheet, else the chat or agent tab on show, else the default
    /// agent's tab, else the default agent, started first. Never a plain shell.
    var briefTarget: BriefTarget {
        BriefTarget.resolve(
            picked: askModel.target, shown: chatPluginID.map(BriefTarget.chat) ?? selectedSession.map(BriefTarget.session),
            tabs: sessions.map { .init(id: $0.id, provider: $0.provider.id, isAgent: $0.provider.isAgent) },
            chats: document.chatAgents.available.map(\.pluginID), defaultAgent: defaultProvider)
    }

    /// Agent tabs that are open and the chat agents, by the names their tabs show.
    var briefOpenChoices: [BriefTargetChoice] {
        let agents = sessions.filter(\.provider.isAgent)
        let tabs = agents.map { session in
            // Two tabs of one agent are told apart by number.
            let same = agents.filter { $0.provider.id == session.provider.id }
            let number = same.count > 1 ? " \((same.firstIndex { $0.id == session.id } ?? 0) + 1)" : ""
            return BriefTargetChoice(target: .session(session.id), title: session.title + number, icon: session.icon)
        }
        let chats = document.chatAgents.available.map {
            BriefTargetChoice(target: .chat($0.pluginID), title: $0.title, icon: "bubble.left.and.bubble.right")
        }
        return tabs + chats
    }

    /// Agents a brief can start in a new tab.
    var briefStartChoices: [BriefTargetChoice] {
        agentChoices.map { BriefTargetChoice(target: .start($0.id), title: $0.title, icon: $0.icon) }
    }

    func choice(for target: BriefTarget) -> BriefTargetChoice? {
        (briefOpenChoices + briefStartChoices).first { $0.target == target }
    }
}
