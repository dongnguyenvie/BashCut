import BashCutAgent
import Foundation

/// The one-time split of a memo into lessons, preferences and facts (#72). The memo stays as notes; an agent reads it
/// and queues what it says with `knowledge split-memo`, and the user reviews the entries in the inbox.
extension AgentKnowledgeModel {
    func loadMemoSplitOffers() {
        guard let store else { return }
        memoSplitOffers = Set(KnowledgeScope.allCases.filter(store.memoNeedsSplit))
    }

    /// Puts the split request in the open agent's input for the user to send.
    func askAgentToSplit(_ scope: KnowledgeScope) {
        if askAgent?(AgentKnowledgeStore.splitRequest(scope)) == true {
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
