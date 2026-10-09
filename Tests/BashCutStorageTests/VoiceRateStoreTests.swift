import BashCutStorage
import Foundation
import Testing

/// Speaking rates measured on synthesized takes, per voice (P0-C2, P0-C4).
struct VoiceRateStoreTests {
    @Test("Rates are kept per voice and language with percentiles; the newest 30 stay")
    func store() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VoiceRateStore(url: folder.appendingPathComponent("voice-rates.json"))
        for rate in stride(from: 3.0, through: 6.0, by: 0.1) { store.record(voice: "p/Mai Anh", language: "vi", unit: "syllables", rate: rate) }
        store.record(voice: "p/Adam", language: "en", unit: "words", rate: 2.5)
        store.record(voice: "p/Adam", language: "en", unit: "words", rate: .nan)
        let rows = try #require(store.summary().array).map(\.object)
        #expect(rows.count == 2)
        let mai = try #require(rows.first { $0["voice"]?.string == "p/Mai Anh" })
        #expect(mai["samples"]?.int == 30 && mai["unit"]?.string == "syllables")
        #expect((mai["p10"]?.double ?? 0) < (mai["p90"]?.double ?? 0))
        #expect(store.summary(voice: "p/Adam").array.first?.object["samples"]?.int == 1)
    }
}
