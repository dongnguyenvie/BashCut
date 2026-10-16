import Foundation
import Testing

@testable import BashCutProject

/// What a later `plan.apply` does with the captions an earlier one built and `captions group` regrouped (#628).
struct PlanCutCaptionsTests {
    let base = PlanCutTests()

    /// The phrase "các bạn ơi giá năm chục" as one clip, captions from speech, and a music bed at `volume` dB.
    func list(volume: Double = -6, captions: String = #"{"from":"speech","maxChars":24}"#) -> String {
        #"""
        {"clips":[{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"}],
        "captions":\#(captions),"music":{"media":"song","volumeDb":\#(volume)}}
        """#
    }

    func apply(_ json: String, on project: Project) throws -> Project {
        let spec = try base.spec(json)
        let clips = PlanCut.resolve(spec, project: project, transcripts: ["m": base.transcript]).clips
        let built = try PlanCut.build(spec, clips: clips, on: project, transcripts: ["m": base.transcript])
        return try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
    }

    func cues(_ project: Project) -> [Item] {
        project.tracks.flatMap(\.items).filter { $0["captionMedia"] != nil }.sorted { $0.at < $1.at }
    }

    /// The built captions regrouped by hand into "các bạn ơi" and "giá năm chục", as `captions group` does.
    func regrouped(_ project: Project, mark: JSONValue? = nil) throws -> Project {
        let words = spans(project)
        try #require(words.count == 6)
        let grouped = try CaptionGrouping.operation(
            project, words: words, groups: [[0, 1, 2], [3, 4, 5]], author: .agent, mark: mark)
        return try project.applying(grouped.operation).project
    }

    /// The words of the captions in timeline frames.
    func spans(_ project: Project) -> [ReviewSync.WordSpan] {
        cues(project).flatMap { cue in
            (cue["words"]?.array ?? []).compactMap { word -> ReviewSync.WordSpan? in
                guard let at = word.object["at"]?.int, let dur = word.object["dur"]?.int,
                    let text = word.object["text"]?.string
                else { return nil }
                return ReviewSync.WordSpan(at: cue.at + at, end: cue.at + at + dur, text: text)
            }
        }
    }

    /// "xin chào" and "các bạn ơi giá năm chục" as two clips, with the given captions.
    func twoClips(captions: String = #"{"from":"speech","maxChars":24}"#, volume: Double = -6) -> String {
        #"""
        {"clips":[{"id":"b","media":"m","quote":"xin chào"},{"id":"a","media":"m","quote":"các bạn ơi giá năm chục"}],
        "captions":\#(captions),"music":{"media":"song","volumeDb":\#(volume)}}
        """#
    }

    @Test("Chosen groups survive an apply that changes the clips: words heard in one grouped cue stay together (B3)")
    func keepsChosenGroupsWhenClipsChange() throws {
        let grouped = try regrouped(try apply(list(), on: base.project()), mark: CaptionGrouping.manualMark)
        let after = try apply(twoClips(), on: grouped)
        #expect(cues(after).map(\.text) == ["xin chào", "các bạn ơi", "giá năm chục"])
        #expect(cues(after).allSatisfy { $0[CaptionGrouping.field] == CaptionGrouping.manualMark && $0[PlanCut.tag] != nil })
        // The grouped cues keep the digest of what was generated, so the next unchanged apply keeps them as they are.
        let again = try apply(twoClips(volume: -3), on: after)
        #expect(cues(again) == cues(after))
    }

    @Test("Rule groups survive an apply that changes the clips: the rule runs again and breaks at the new cut (B3, B6)")
    func keepsRuleGroupsWhenClipsChange() throws {
        let built = try apply(list(), on: base.project())
        let rule = CaptionGrouping.Rule(maxChars: 100, maxSeconds: 10, breakGapSeconds: 5)
        let words = spans(built)
        let groups = CaptionGrouping.groups(words, rule: rule, fps: built.fps.value, cuts: CaptionGrouping.cuts(built))
        let grouped = try built.applying(
            CaptionGrouping.operation(built, words: words, groups: groups, author: .agent, mark: rule.json).operation).project
        #expect(cues(grouped).map(\.text) == ["các bạn ơi giá năm chục"])
        let after = try apply(twoClips(), on: grouped)
        #expect(cues(after).map(\.text) == ["xin chào", "các bạn ơi giá năm chục"])
        #expect(cues(after).allSatisfy { CaptionGrouping.Rule(json: $0[CaptionGrouping.field]) == rule })
    }

    @Test("Rule grouping breaks at cuts between clips unless told not to (B6)")
    func breaksAtCuts() throws {
        let built = try apply(twoClips(), on: base.project())
        let words = spans(built)
        let cuts = CaptionGrouping.cuts(built)
        #expect(cuts.count == 1)
        let joined = CaptionGrouping.Rule(maxChars: 100, maxSeconds: 10, breakGapSeconds: 5, breakAtCuts: false)
        #expect(CaptionGrouping.groups(words, rule: joined, fps: built.fps.value, cuts: cuts).count == 1)
        var split = joined
        split.breakAtCuts = true
        #expect(CaptionGrouping.groups(words, rule: split, fps: built.fps.value, cuts: cuts).map(\.count) == [2, 6])
    }

    @Test("A music-only apply keeps hand-grouped captions as they are, with no second set")
    func keepsGroupedCaptions() throws {
        let built = try apply(list(), on: base.project())
        #expect(cues(built).count == 1)
        let grouped = try regrouped(built)
        let hand = cues(grouped)
        #expect(hand.map(\.text) == ["các bạn ơi", "giá năm chục"])
        // Grouping keeps the plan marks, so the cues stay the plan's captions.
        #expect(hand.allSatisfy { $0[PlanCut.tag] == .string("captions") && $0[PlanCut.captionsTag] != nil })

        let after = try apply(list(volume: -4), on: grouped)
        #expect(cues(after) == hand)
        #expect(after.track(role: TrackRole.music)?.items.first?["volumeDb"] == .number(-4))
    }

    @Test("An apply whose captions change replaces the hand-grouped ones instead of stacking a second set")
    func replacesGroupedCaptions() throws {
        let grouped = try regrouped(try apply(list(), on: base.project()))
        let after = try apply(list(captions: #"{"from":"speech","style":{"size":0.07}}"#), on: grouped)
        let cues = cues(after)
        #expect(cues.map(\.text) == ["các bạn ơi giá năm chục"])
        #expect(cues.allSatisfy { $0["textStyle"]?.object["size"] == .number(0.07) })
    }

    @Test("Speech captions the plan did not build under its captions are refused, not stacked")
    func refusesForeignCaptions() throws {
        let grouped = try regrouped(try apply(list(), on: base.project()))
        // Cues grouped before the marks were kept (or made by captions generate) carry no plan mark.
        var project = grouped
        for track in project.tracks.indices {
            for item in project.tracks[track].items.indices {
                project.tracks[track].items[item].fields[PlanCut.tag] = nil
            }
        }
        #expect(throws: ProjectError.self) { try apply(list(volume: -4), on: project) }
    }
}

/// `clip volume` (#628): the gain of clips and their linked partners as one group.
struct ClipVolumeTests {
    @Test("Clip volume sets volumeDb on a clip and its linked sound; items without sound are skipped")
    func volume() throws {
        let captions = PlanCutCaptionsTests()
        var project = try captions.apply(captions.list(), on: captions.base.project())
        let (operations, skipped) = try project.volumeOperations(["plan-a", "plan-a-audio", "plan-music", "nope"], db: -4)
        #expect(skipped == ["nope"])
        project = try project.applying(.group(label: "Volume", author: .agent, ops: operations)).project
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        #expect(operations.count == 3)
        for id in ["plan-a", "plan-a-audio", "plan-music"] { #expect(items[id]?["volumeDb"] == .number(-4)) }
        let cue = try #require(captions.cues(project).first)
        #expect(try project.volumeOperations([cue.id], db: -4).skipped == [cue.id])
        #expect(throws: ProjectError.self) { try project.volumeOperations(["plan-a"], db: 40) }
    }
}
