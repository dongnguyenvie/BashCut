import BashCutProject
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

    @Test("The ledger (P3-I2): exports with a project get an ID, revision, fingerprint, snapshot and post links")
    func ledger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportHistoryStore(limit: 2)
        var caption = Item(id: "c", at: 0, duration: 30)
        caption["text"] = .string("Hello there")
        let project = try Project(name: "Ledger").applying(.group(label: "Setup", author: .user, ops: [
            .insert(track: "t1", item: caption), .upsertSection(id: "hook", label: "Hook", atFrame: 0),
        ])).project

        _ = try store.record(metrics(index: 1), projectRoot: root)
        let first = try store.record(metrics(index: 2), projectRoot: root, project: project).current
        let id = try #require(first.id)
        #expect(id.hasPrefix("x-") && first.rev == project.revision && first.fingerprint?.object["hook"] != nil)
        let snapshot = try #require(store.snapshot(id, projectRoot: root))
        #expect(snapshot.sections.map(\.label) == ["Hook"] && snapshot.words.map(\.text) == ["Hello", "there"])

        let linked = try store.addLink(ExportLink(url: "https://t.co/1", platform: "tiktok"), to: nil, projectRoot: root)
        _ = try store.addLink(ExportLink(url: "https://t.co/1", platform: "reels"), to: id, projectRoot: root)
        #expect(linked.id == id)
        #expect(try store.entry(id, projectRoot: root).entry.links?.map(\.platform) == ["reels"], "same URL replaces")
        #expect(try store.entry("0", projectRoot: root).entry.id == nil, "an older export by index")
        #expect(throws: ProjectError.self) { try store.entry("x-missing", projectRoot: root) }

        _ = try store.record(metrics(index: 3), projectRoot: root, project: project)
        _ = try store.record(metrics(index: 4), projectRoot: root, project: project)
        #expect(store.snapshot(id, projectRoot: root) == nil, "a dropped export's snapshot goes with it")
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
