import BashCutProject
import BashCutStorage
import Foundation
import Testing

/// The result card of a run that exported (#448).
struct RunResultTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func export(_ name: String, at seconds: Double, lufs: Double? = -14) -> StoredExportMetrics {
        StoredExportMetrics(
            path: "/tmp/\(name).mp4", preset: "vertical-1080", duration: 31.234, bytes: 1_000, cutCount: 13,
            captionCount: 4, includedSubRip: false, speechCoverage: 0.8, integratedLUFS: lufs, truePeakDbTP: -1.2,
            loudnessRangeLU: nil, loudnessVerified: true, appliedGainDb: nil,
            completedAt: start.addingTimeInterval(seconds))
    }

    @Test("Only the run's exports count, newest first and once per file, with the issues still open")
    func result() throws {
        let history = [
            export("old", at: -60), export("tiktok", at: 100), export("youtube", at: 200, lufs: nil), export("tiktok", at: 300),
        ]
        let review = ReviewSummary([
            ReviewIssue(id: "gap:1", title: "", detail: "", frame: 1, severity: .error),
            ReviewIssue(id: "cut:2", title: "", detail: "", frame: 2, severity: .warning),
            ReviewIssue(id: "cut:3", title: "", detail: "", frame: 3, severity: .info),
        ], coverage: .null)
        let result = try #require(RunResult.make(
            run: 2, since: start, history: history, review: review, recipe: "bashcut.vlog:travel"))
        #expect(result.outputs.map(\.path) == ["/tmp/tiktok.mp4", "/tmp/youtube.mp4"])
        #expect(result.cuts == 12 && result.errors == 1 && result.warnings == 1 && result.issuesLeft == 2)
        let json = result.json.object
        #expect(json["path"] == .string("/tmp/tiktok.mp4") && json["cuts"] == .integer(12))
        #expect(json["duration"] == .number(31.23) && json["lufs"] == .number(-14))
        #expect(json["review"]?.object["errors"] == .integer(1) && json["recipe"] == .string("bashcut.vlog:travel"))
        #expect(json["outputs"]?.array.count == 2 && json["thumbnail"] == .null)
        #expect(RunResult.make(run: 2, since: start.addingTimeInterval(400), history: history, review: review, recipe: nil) == nil)
    }

    @Test("The export history lists every recorded export")
    func historyAll() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExportHistoryStore()
        #expect(try store.all(projectRoot: root).isEmpty)
        _ = try store.record(export("a", at: 0), projectRoot: root)
        _ = try store.record(export("b", at: 1), projectRoot: root)
        #expect(try store.all(projectRoot: root).map(\.path) == ["/tmp/a.mp4", "/tmp/b.mp4"])
    }
}
