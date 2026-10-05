import BashCutAgent
import Foundation

/// The one-time split of a memo into lessons, preferences and facts (#72). The memo stays as notes; an agent reads it
/// and queues what it says with `knowledge split-memo`, and the user reviews the entries in the inbox.
extension AgentKnowledgeModel {
    func loadMemoSplitOffers() {
        guard let store else { return }
        memoSplitOffers = Set(KnowledgeScope.allCases.filter(store.memoNeedsSplit))
    }

    /// The line agents see under a memo that was not split yet.
    static func splitHint(_ scope: KnowledgeScope) -> String {
        "Not split into lessons, preferences and facts yet: when the user asks, queue what it says for review with "
            + "`bashcut knowledge split-memo <entries.json>\(scope == .user ? " --scope user" : "")`."
    }

    /// What the agent is asked to do.
    static func splitRequest(_ scope: KnowledgeScope) -> String {
        let memo = scope == .project ? "the project memo" : "the notes for every project"
        let flag = scope == .project ? "" : " --scope user"
        return "Split \(memo) into structured knowledge, once. Read it with `bashcut knowledge get`, write what it "
            + "says to a JSON file as lessons (title, symptom, cause, fix, tags), preferences (my taste: key, value)"
            + (scope == .project ? " and project facts (key, value)" : "")
            + ", then run `bashcut knowledge split-memo <file.json>\(flag)`. Keep each entry short and leave long "
            + "notes, such as style measurements, in the memo; do not change the memo. Everything waits in the "
            + "Knowledge inbox for my review."
    }

    /// Puts the split request in the open agent's input for the user to send.
    func askAgentToSplit(_ scope: KnowledgeScope) {
        if askAgent?(Self.splitRequest(scope)) == true {
            message = String(localized: "The request is in the agent's input: send it there")
        } else {
            message = String(localized: "Open an agent in the dock first, then ask again")
        }
    }

    /// Keeps the memo as notes only; the split is not offered again.
    func keepMemoAsNotes(_ scope: KnowledgeScope) {
        do {
            try requireStore().keepMemo(scope, source: KnowledgeSource(agent: Self.userSource))
            loadMemoSplitOffers()
            message = String(localized: "Kept as notes")
        } catch { message = error.localizedDescription }
    }
}
