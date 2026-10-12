import BashCutAgent
import BashCutAutomation
import BashCutProject
import Foundation

/// The user's verdicts on agents' changes (P3-I1), recorded where BashCut sees them: an undo of an agent's step, the
/// next edit after one (on the same items or not), a dismissed change notice, an answer to the scope guard. Facts
/// only, kept per project in `.bashcut/knowledge/verdicts.jsonl` and read with `knowledge verdicts`.
extension ProjectDocument {
    func recordVerdict(_ verdict: KnowledgeVerdict) {
        guard fileURL != nil else { return }
        do {
            try agents.knowledgeStore.recordVerdict(verdict)
            DebugLog.write("verdict", "\(verdict.verdict.rawValue) (\(verdict.signal.rawValue)) \(verdict.subject): \(verdict.label)")
        } catch {
            DebugLog.write("verdict", "not recorded: \(error.localizedDescription)")
        }
    }

    /// The current agent change, when it is still the latest step.
    private var openAgentChange: AgentChangeRecord? {
        guard let change = agentChange, change.afterRevision == project.revision else { return nil }
        return change
    }

    /// A verdict on the agent change the notice shows.
    func recordAgentChangeVerdict(_ verdict: KnowledgeVerdict.Kind, signal: KnowledgeVerdict.Signal) {
        guard let change = openAgentChange else { return }
        recordVerdict(KnowledgeVerdict(
            verdict: verdict, signal: signal, subject: change.command, label: change.label,
            agent: change.author.rawValue, rev: change.afterRevision, items: Array(change.changedIDs)))
    }

    /// The user undoes an agent's step (the latest one, or an older one further back); called before the undo.
    func recordUndoVerdict(by author: Author, before: Project) {
        guard !author.isAgent, author != .external, let step = history.lastUndo, step.author.isAgent else { return }
        let change = openAgentChange.flatMap { $0.label == step.label && $0.author == step.author ? $0 : nil }
        recordVerdict(KnowledgeVerdict(
            verdict: .undo, signal: .undo, subject: change?.command, label: step.label, agent: step.author.rawValue,
            rev: step.revision ?? before.revision, items: change.map { Array($0.changedIDs) } ?? []))
    }

    /// The user's first edit after an agent's change: on the same items it is an edit of the change, otherwise the
    /// change stays (kept).
    func recordNextEditVerdict(by author: Author, label: String, before: Project) {
        guard author != .external, !["Undo", "Redo"].contains(label), let change = agentChange,
            change.afterRevision == before.revision
        else { return }
        let touched = Set(project.itemChanges(from: before).map(\.itemID)).intersection(change.changedIDs)
        recordVerdict(KnowledgeVerdict(
            verdict: touched.isEmpty ? .keep : .edit, signal: touched.isEmpty ? .nextEdit : .edit,
            subject: change.command, label: change.label, agent: change.author.rawValue, rev: change.afterRevision,
            items: touched.isEmpty ? Array(change.changedIDs) : Array(touched)))
    }
}
