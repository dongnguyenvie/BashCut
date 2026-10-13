import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// The run panel's progress (#447) derived from the run log, and the range filter of `review run --from --to`.
struct RunProgressTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ kind: String, at seconds: Double, run: Int = 1, _ fields: [String: JSONValue] = [:])
        -> [String: JSONValue]
    {
        var entry = fields
        entry["kind"] = .string(kind)
        entry["run"] = .integer(run)
        entry["time"] = .string(ISO8601DateFormatter().string(from: start.addingTimeInterval(seconds)))
        return entry
    }

    private func stage(_ id: String, _ status: String? = nil, at seconds: Double, _ more: [String: JSONValue] = [:])
        -> [String: JSONValue]
    {
        var fields = more
        fields["stage"] = .string(id)
        if let status { fields["status"] = .string(status) }
        return entry("stage", at: seconds, fields)
    }

    @Test("Stages, the current one with its step, progress and ETA, and the times come from the current run")
    func progress() throws {
        var project = try ProjectFixtures.linkedPair()
        project["plan"] = .object(["stages": .object([
            "colour": .object(["required": .bool(false)]),
            "motion-graphics": .object(["required": .bool(true)]),
        ])])
        let entries = [
            entry("stage", at: -500, run: 0, ["stage": .string("export"), "status": .string("done")]),
            entry("start", at: 0),
            stage("survey", "started", at: 10),
            stage("survey", "done", at: 70),
            stage("rough-cut", at: 80),
            stage("rough-cut", "started", at: 100, [
                "text": .string("Cutting 12 shots"), "progress": .number(1.4), "eta": .integer(90),
            ]),
        ]
        let progress = try #require(RunProgress.make(project, entries: entries))
        let ids = progress.stages.map(\.id)
        #expect(ids.first == "survey" && ids.last == "export")
        #expect(!ids.contains("colour") && !ids.contains("intake") && ids.contains("motion-graphics"))
        #expect(ids.firstIndex(of: "motion-graphics") == ids.firstIndex(of: "review").map { $0 - 1 })
        let rows = Dictionary(uniqueKeysWithValues: progress.stages.map { ($0.id, $0) })
        #expect(rows["survey"]?.status == .done)
        #expect(rows["survey"]?.endedAt?.timeIntervalSince(try #require(rows["survey"]?.startedAt)) == 60)
        #expect(rows["rough-cut"]?.status == .active && rows["story"]?.status == .pending)
        #expect(progress.current == "rough-cut" && progress.text == "Cutting 12 shots")
        #expect(progress.progress == 1, "progress is clamped to 0…1")
        #expect(progress.exportedAt == nil, "an export of an earlier run does not count")
        #expect(!progress.finished && progress.lastActivity == start.addingTimeInterval(100))
        let now = start.addingTimeInterval(130)
        #expect(progress.elapsed(now: now) == 130)
        #expect(progress.stageElapsed(now: now) == 50)
        #expect(progress.remaining(now: now) == 60)
        #expect(progress.remaining(now: start.addingTimeInterval(400)) == 0)
        let json = progress.json(now: now).object
        #expect(json["current"] == .string("rough-cut") && json["remaining"] == .integer(60))
        #expect(json["elapsed"] == .integer(130) && json["finished"] == .bool(false))
    }

    @Test("The run finishes when it exports with nothing started after, or with an end entry")
    func finished() throws {
        let project = try ProjectFixtures.linkedPair()
        let exported = [entry("start", at: 0), stage("review", "done", at: 50), stage("export", "done", at: 80)]
        let done = try #require(RunProgress.make(project, entries: exported))
        #expect(done.finished && done.current == nil && done.exportedAt != nil)
        let again = try #require(RunProgress.make(project, entries: exported + [stage("captions", at: 90)]))
        #expect(!again.finished && again.current == "captions" && again.exportedAt != nil)
        let ended = try #require(RunProgress.make(project, entries: [entry("start", at: 0), stage("survey", at: 5), entry("end", at: 40)]))
        #expect(ended.finished && ended.elapsed(now: start.addingTimeInterval(500)) == 40)
        #expect(RunProgress.make(project, entries: [entry("start", at: 0), entry("note", at: 1)]) == nil)
    }

    @Test("Short stage names map to the checklist's IDs")
    func aliases() {
        #expect(RunProgress.stageID("cut") == "rough-cut")
        #expect(RunProgress.stageID(" Color ") == "colour")
        #expect(RunProgress.stageID("motion-graphics") == "motion-graphics")
        #expect(WorkflowChecklist.stageStatuses.contains("started"))
    }

    @Test("An issue touches a range by its span, or by its frame without one")
    func issueRange() {
        let point = ReviewIssue(id: "gap:10", title: "", detail: "", frame: 10)
        let span = ReviewIssue(id: "shot-long:v1", title: "", detail: "", frame: 40, endFrame: 100)
        #expect(TimelineReview.issue(point, overlaps: 0..<11) && !TimelineReview.issue(point, overlaps: 11..<50))
        #expect(TimelineReview.issue(span, overlaps: 90..<120) && TimelineReview.issue(span, overlaps: 0..<41))
        #expect(!TimelineReview.issue(span, overlaps: 100..<200) && !TimelineReview.issue(span, overlaps: 0..<40))
    }
}
