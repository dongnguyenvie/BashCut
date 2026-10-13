import BashCutStorage
import Foundation
import Testing

/// "My voices": saved clones in the user's folder (#532).
struct VoiceCloneStoreTests {
    private func draft(_ name: String) -> VoiceClone {
        VoiceClone(
            id: "", name: name, language: "vi", providers: ["vieneu.local"], sourceDescription: "intro.mov 2.0–8.5 s",
            durationSeconds: 6.5, consent: .init(by: "user", statement: .own), reference: "")
    }

    @Test("A clone is saved with its reference and voice.json, listed, reused by ID and removed")
    func addListRemove() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VoiceCloneStore(root: folder.appendingPathComponent("Voices"))
        let source = folder.appendingPathComponent("trimmed.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: source)

        let first = try store.add(draft("Giọng Nolan"), reference: source)
        #expect(first.id == "clone-giong-nolan" && first.reference == "reference.wav")
        let second = try store.add(draft("Giọng Nolan"), reference: source)
        #expect(second.id == "clone-giong-nolan-2")
        #expect(FileManager.default.fileExists(atPath: store.referenceURL(first).path))
        let json = try String(contentsOf: store.root.appendingPathComponent("clone-giong-nolan/voice.json"), encoding: .utf8)
        #expect(json.contains("\"statement\" : \"own\"") && json.contains("\"providers\""))

        #expect(Set(store.list().map(\.id)) == [first.id, second.id])
        let again = try #require(store.clone(first.id))
        #expect(again.name == "Giọng Nolan" && again.consent.statement == .own && again.durationSeconds == 6.5)
        #expect(store.clone("../etc") == nil)

        try store.remove(first.id)
        #expect(store.list().map(\.id) == [second.id])
        #expect(throws: (any Error).self) { try store.remove(first.id) }
        #expect(throws: (any Error).self) { try store.add(draft("  "), reference: source) }
    }

    @Test("Slugs fold Vietnamese and drop punctuation")
    func slugs() {
        #expect(VoiceCloneStore.slug("Đăng Khoa!") == "dang-khoa")
        #expect(VoiceCloneStore.slug("  ") == "voice")
        #expect(VoiceCloneStore.slug("Adam 2") == "adam-2")
    }
}
