import BashCutStorage
import Foundation
import Testing

struct ExportHistoryTests {
    @Test("Export history persists metrics, compares the previous export and respects its limit")
    func history() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportHistoryStore(limit: 2)

        let first = try store.record(metrics(index: 1), projectRoot: root)
        #expect(first.comparison == nil)

        let second = try store.record(metrics(index: 2), projectRoot: root)
        #expect(second.comparison?.duration == 1)
        #expect(second.comparison?.bytes == 100)
        #expect(second.comparison?.cutCount == 1)
        #expect(second.comparison?.captionCount == 1)
        #expect(second.comparison?.speechCoverage == 0.1)
        #expect(second.comparison?.integratedLUFS == 1)

        _ = try store.record(metrics(index: 3), projectRoot: root)
        let latest = try store.latest(projectRoot: root)
        let restored = try #require(latest)
        #expect(restored.current == metrics(index: 3))
        #expect(restored.comparison?.duration == 1)

        let data = try Data(
            contentsOf: root.appendingPathComponent(".bashcut/export-history.json"))
        let entries = try JSONDecoder.iso8601.decode([StoredExportMetrics].self, from: data)
        #expect(entries.map(\.preset) == ["preset-2", "preset-3"])
    }

    private func metrics(index: Int) -> StoredExportMetrics {
        StoredExportMetrics(
            path: "/tmp/export-\(index).mp4", preset: "preset-\(index)",
            duration: Double(index + 9), bytes: Int64(index * 100), cutCount: index,
            captionCount: index + 2, includedSubRip: true,
            speechCoverage: Double(index) / 10, integratedLUFS: Double(index - 16),
            truePeakDbTP: -1, loudnessRangeLU: 4, loudnessVerified: true,
            appliedGainDb: 1, completedAt: Date(timeIntervalSince1970: Double(index)))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
