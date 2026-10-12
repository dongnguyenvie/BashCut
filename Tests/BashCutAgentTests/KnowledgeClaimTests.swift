import BashCutAgent
import BashCutProject
import Foundation
import Testing

/// P3-I5: the claims ledger and the creator profile.
struct KnowledgeClaimTests {
    private func store() -> (AgentKnowledgeStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (AgentKnowledgeStore(project: root.appendingPathComponent("p"), user: root.appendingPathComponent("u")), root)
    }

    @Test("Claims are set with text and source, replaced by key and removed")
    func claims() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let author = KnowledgeSource(agent: "claude")
        try store.setClaim(key: "area", text: "528 ha", source: "https://vi.wikipedia.org/wiki/Hồ_Tây", author: author)
        try store.setClaim(key: "area", text: "500 ha", source: "user", author: author)
        #expect(try store.claims().map(\.text) == ["500 ha"])
        #expect(throws: KnowledgeError.self) { try store.setClaim(key: "x", text: "1", source: " ", author: author) }
        try store.setClaim(key: "area", text: nil, source: nil, author: author)
        #expect(try store.claims().isEmpty)
        #expect(throws: KnowledgeError.self) { try store.setClaim(key: "area", text: nil, source: nil, author: author) }
        let unsaved = AgentKnowledgeStore(project: nil, user: root.appendingPathComponent("u"))
        #expect(try unsaved.claims().isEmpty)
    }

    @Test("creator.* keys are checked and shown as one profile, not among the preferences")
    func creator() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: KnowledgeError.self) {
            try CreatorProfile.validate(key: "creator.shoeSize", value: "42", mediaExists: { _ in true })
        }
        #expect(throws: KnowledgeError.self) {
            try CreatorProfile.validate(key: "creator.voiceSamples", value: "m1, m9", mediaExists: { $0 == "m1" })
        }
        try CreatorProfile.validate(key: "creator.voiceSamples", value: "m1", mediaExists: { $0 == "m1" })
        let source = KnowledgeSource(agent: "user")
        try store.setValue(.prefs, key: "creator.handle", value: "@lan", scope: .user, source: source)
        try store.setValue(.prefs, key: "creator.platforms", value: "tiktok, youtube", scope: .project, source: source)
        try store.setValue(.prefs, key: "pace", value: "calm", scope: .user, source: source)
        let summary = store.summary()
        #expect(summary.prefs.map(\.key) == ["pace"])
        #expect(summary.creator == .object([
            "handle": .string("@lan"), "platforms": .array([.string("tiktok"), .string("youtube")]),
        ]))
        #expect(summary.text.contains("Creator: handle = @lan; platforms = tiktok, youtube"))
    }
}
