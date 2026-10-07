import Foundation
import Testing

@testable import BashCutProject

/// Negative controls (P1-E7): each detector is shown a fixture with the fault it exists to find and must report it.
/// "Gates that have never failed are not gates."
struct NegativeControlTests {
    @Test("A one-frame gap on Main is an error")
    func oneFrameGap() throws {
        let project = try ReviewPictureTests().project([("a", "m", 30)])
        var gapped = project
        let main = gapped.tracks.firstIndex { $0.id == "v1" }!
        gapped.tracks[main].items.append(Item(id: "b", media: "m", at: 31, duration: 30))
        let gap = TimelineReview.run(gapped).first { $0.id == "gap-b" }
        #expect(gap?.severity == .error && gap?.frame == 30)
    }

    @Test("A caption 0.3 s after its word is measured as 9 frames late")
    func captionShift() throws {
        var project = try ReviewPictureTests().project([("a", "m", 300)])
        var caption = Item(id: "cap", at: 39, duration: 30)
        caption["text"] = .string("xin chào")
        let captions = project.tracks.firstIndex { $0.role == TrackRole.captions }!
        project.tracks[captions].items = [caption]
        let words = [ReviewSync.WordSpan(at: 30, end: 45, text: "xin"), ReviewSync.WordSpan(at: 45, end: 60, text: "chào")]
        let events = ReviewSync.json(project, words: words, kinds: [.captions]).object["events"]?.array ?? []
        let row = try #require(events.first { $0.object["item"] == .string("cap") }).object
        #expect(row["word"]?.object["offsetFrames"] == .integer(9))
    }

    @Test("A clip that starts inside a word is an error")
    func cutInsideWord() {
        let (project, transcripts) = ReviewInvariantsTests().project([Item(id: "x", media: "m", at: 0, duration: 30, sourceIn: 36)])
        #expect(TimelineReview.wordCutIssues(project, transcripts: transcripts).first?.id == "cut-in-word-x-in")
    }

    @Test("A frozen second is found when the project allows half a second")
    func frozenSecond() throws {
        var project = try ReviewPictureTests().project([("a", "m", 150)])
        project["review"] = .object(["maxStillSeconds": .number(0.5)])
        let measured = ReviewPictureTests().picture(project) { frame in (0.5, 0.2, frame > 45 && frame <= 75 ? 0.001 : 0.05) }
        #expect(TimelineReview.run(project, context: ReviewContext(picture: measured)).contains { $0.id.hasPrefix("still-") })
    }

    @Test("An end card 15 dB under the voice before it shows in the speech windows")
    func quietEndCard() throws {
        let project = try ReviewPictureTests().project([("a", "m", 300)])
        // Ten seconds of voice at −16 LUFS, then the last two at −31.
        let speech = MixMeasure.Curve(momentary: (0..<100).map { $0 < 50 ? -16 : $0 < 80 ? -100 : -31 })
        let words = [ReviewSync.WordSpan(at: 0, end: 150, text: "a"), ReviewSync.WordSpan(at: 240, end: 300, text: "b")]
        let windows = (MixMeasure.json(project, speech: speech, music: nil, effects: nil, words: words)
            .object["speechWindows"]?.array ?? []).map(\.object)
        let first = try #require(windows.first?["voice"]?.object["median"]?.double)
        let last = try #require(windows.last?["voice"]?.object["median"]?.double)
        #expect(windows.count == 2 && first - last == 15)
    }
}

/// Review coverage, delivered-file QC and reference comparison (P1-E5, E6, E8).
struct ReviewMechanicsTests {
    @Test("Coverage lists measured, stale and unchecked checks; a picture that never changes is unreliable, not passed")
    func coverage() throws {
        let project = try ReviewPictureTests().project([("a", "m", 120)])
        let bare = TimelineReview.coverage(project, context: ReviewContext()).object
        #expect(bare["notChecked"]?.array.contains { $0.string?.hasPrefix("picture") == true } == true)
        #expect(bare["unsetLimits"]?.array.contains(.string("maxShotSeconds")) == true)
        let frozen = ReviewPictureTests().picture(project) { _ in (0.5, 0.2, 0.001) }
        let context = ReviewContext(picture: frozen)
        #expect(TimelineReview.coverage(project, context: context).object["unreliable"]?.array.count == 1)
        #expect(TimelineReview.run(project, context: context).contains { $0.id == "picture-unreliable" })
        var older = project
        older.revision += 1
        #expect(TimelineReview.coverage(older, context: context).object["stale"]?.array.count == 1)
    }

    @Test("Delivered facts: drift over a frame, a wrong size and black inside are errors; silence is a note")
    func delivered() throws {
        let project = try ReviewPictureTests().project([("a", "m", 300)])
        let facts = DeliveredFacts(
            revision: project.revision, preset: "tiktok", path: "/tmp/out.mp4", videoStart: 0, audioStart: 0.1, fps: 30,
            expectedFps: 30, size: (720, 1280), expectedSize: (1080, 1920), duration: 10,
            black: [0...0.5, 4...5], silence: [6...7])
        let issues = TimelineReview.deliveredIssues(project, delivered: [facts])
        let errors = Set(issues.filter { $0.severity == .error }.map(\.id))
        #expect(errors == ["delivered-drift-tiktok", "delivered-size-tiktok", "delivered-black-tiktok-120"])
        #expect(issues.first { $0.id.hasPrefix("delivered-silence") }?.severity == .info)
        var stale = facts
        stale.revision += 1
        #expect(TimelineReview.deliveredIssues(project, delivered: [stale]).isEmpty)
    }
}

/// The reference and ours by the same functions (P1-E8).
struct ReviewCompareTests {
    @Test("Metrics side by side with deltas; within only where the project gives a tolerance")
    func compare() throws {
        let reference = MediaAnalysisTests().record()
        var ours = reference
        ours.corrections.add = [150]
        let rows = (ReviewCompare.json(reference: reference, ours: ours, tolerances: ["shots": 0]).object["rows"]?.array ?? [])
            .map(\.object)
        let shots = try #require(rows.first { $0["metric"] == .string("shots") })
        #expect(shots["reference"] == .number(3) && shots["ours"] == .number(4) && shots["delta"] == .number(1))
        #expect(shots["within"] == .bool(false))
        let luma = try #require(rows.first { $0["metric"] == .string("lumaMedian") })
        #expect(luma["delta"] == .number(0) && luma["within"] == nil)
        #expect(rows.contains { $0["metric"] == .string("levelRangeDb") })
    }
}
