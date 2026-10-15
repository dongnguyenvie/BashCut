import BashCutAgent
import Foundation
import Testing

struct BriefTargetTests {
    private let claude = UUID()
    private let codex = UUID()
    private let shell = UUID()
    private var tabs: [BriefTarget.Tab] {
        [.init(id: claude, provider: .claude, isAgent: true), .init(id: codex, provider: .codex, isAgent: true),
         .init(id: shell, provider: .shell, isAgent: false)]
    }

    private func resolve(
        picked: BriefTarget? = nil, shownChat: String? = nil, selected: UUID? = nil, tabs: [BriefTarget.Tab]? = nil,
        chats: [String] = [], defaultAgent: AgentProviderID = .claude
    ) -> BriefTarget {
        BriefTarget.resolve(
            picked: picked, shown: shownChat.map(BriefTarget.chat) ?? selected.map(BriefTarget.session),
            tabs: tabs ?? self.tabs, chats: chats, defaultAgent: defaultAgent)
    }

    @Test("The user's pick wins while it still exists")
    func picked() {
        #expect(resolve(picked: .session(codex), selected: claude) == .session(codex))
        #expect(resolve(picked: .start(.codex), selected: claude) == .start(.codex))
        #expect(resolve(picked: .chat("chat"), selected: claude, chats: ["chat"]) == .chat("chat"))
        #expect(resolve(picked: .session(UUID()), selected: codex) == .session(codex))
        #expect(resolve(picked: .chat("gone"), selected: codex) == .session(codex))
    }

    @Test("Without a pick: the tab on show, then the default agent's tab, then starting it; never a shell")
    func fallback() {
        #expect(resolve(shownChat: "chat", selected: codex, chats: ["chat"]) == .chat("chat"))
        #expect(resolve(selected: codex) == .session(codex))
        #expect(resolve(selected: shell) == .session(claude))
        #expect(resolve(selected: shell, defaultAgent: .codex) == .session(codex))
        #expect(resolve(selected: shell, tabs: [.init(id: shell, provider: .shell, isAgent: false)]) == .start(.claude))
        #expect(resolve(picked: .session(shell), tabs: []) == .start(.claude))
    }

    @Test("The default agent: the one chosen, else the last used, else Claude Code")
    func defaultAgent() {
        let both: [AgentProviderID] = [.claude, .codex]
        #expect(AgentDefault.resolve(chosen: .codex, last: .claude, available: both) == .codex)
        #expect(AgentDefault.resolve(chosen: nil, last: .codex, available: both) == .codex)
        #expect(AgentDefault.resolve(chosen: nil, last: "uninstalled-plugin", available: both) == .claude)
        #expect(AgentDefault.resolve(chosen: "gone", last: nil, available: both) == .claude)
        #expect(AgentDefault.resolve(chosen: nil, last: nil, available: [.codex]) == .codex)
    }
}

struct AgentScreenTests {
    @Test("Trust and setup menus count as questions; the input box does not")
    func asking() {
        #expect(AgentScreen.isAsking("""
            Quick safety check: Is this a project you created or one you trust?
             ❯ No, exit
               Yes, I trust this folder
             Enter to confirm · Esc to cancel
            """))
        #expect(AgentScreen.isAsking("Do you trust the contents of this directory?\n  Press enter to continue"))
        #expect(AgentScreen.isAsking(" Enter\0to\0confirm\0·\0Esc\0to\0cancel"))
        #expect(!AgentScreen.isAsking("╭──────╮\n│ > Try \"edit <filepath> to...\" │\n╰──────╯\n  ? for shortcuts"))
    }
}
