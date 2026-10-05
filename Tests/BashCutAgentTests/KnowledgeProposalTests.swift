import BashCutAgent
import Foundation
import Testing

struct KnowledgeProposalTests {
    private func store() throws -> (store: AgentKnowledgeStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        for url in [project, user] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (AgentKnowledgeStore(project: project, user: user), root)
    }

    private func source(_ agent: String = "claude", _ seconds: TimeInterval = 0) -> KnowledgeSource {
        KnowledgeSource(agent: agent, session: "s1", date: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test("A preference proposal waits in proposals.json; a newer one for the same key replaces it")
    func propose() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.proposeValue(.prefs, key: "pace", value: "calm", scope: .user, source: source())
        let proposal = try store.proposeValue(.prefs, key: " pace ", value: "fast", scope: .user, source: source("codex", 1))

        #expect(proposal.id.hasPrefix("p-") && proposal.key == "pace")
        #expect(try store.valueProposals().map(\.value) == ["fast"])
        #expect(try store.values(.prefs).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("user/proposals.json").path))
        #expect(throws: KnowledgeError.self) {
            try store.proposeValue(.prefs, key: "missing", value: nil, scope: .user, source: source())
        }
        #expect(throws: KnowledgeError.self) {
            try store.proposeValue(.facts, key: "host", value: "An", scope: .user, source: source())
        }
    }

    @Test("Approving applies the value, the user's edit first; the agent stays its source and history records the approval")
    func approve() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = store.signature()
        let proposal = try store.proposeValue(.prefs, key: "pace", value: "calm", scope: .user, source: source())
        #expect(store.signature() != before)

        let value = try #require(try store.approveValue(proposal.id, value: "calm, few cuts", source: source("user", 5)))
        #expect(value.value == "calm, few cuts" && value.source.agent == "claude" && value.scope == .user)
        #expect(try store.valueProposals().isEmpty)
        let change = try #require(store.history(.user).first)
        #expect(change.action == .approve && change.kind == .prefs && change.source.agent == "user")
        #expect(throws: KnowledgeError.self) { try store.approveValue(proposal.id, source: source("user")) }

        let removal = try store.proposeValue(.prefs, key: "pace", value: nil, scope: .user, source: source())
        #expect(try store.approveValue(removal.id, value: "ignored", source: source("user", 6)) == nil)
        #expect(try store.values(.prefs).isEmpty)
    }

    @Test("Rejecting drops the proposal and history keeps what was proposed")
    func reject() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let proposal = try store.proposeValue(.prefs, key: "music", value: "lo-fi", scope: .user, source: source())
        try store.rejectValue(proposal.id, source: source("user", 2))

        #expect(try store.valueProposals().isEmpty && store.values(.prefs).isEmpty)
        let change = try #require(store.history(.user).first)
        #expect(change.action == .reject && change.after == nil)
        guard case .value(let rejected) = change.before else { Issue.record("No value before"); return }
        #expect(rejected.value == "lo-fi" && rejected.source.agent == "claude")
    }
}
