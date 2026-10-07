import Foundation
import Testing

@testable import BashCutProject

/// Invariants as the only default errors (P1-E1) and review rounds (P1-E2).
struct ReviewInvariantsTests {
    /// 30 fps; media m (20 s, with sound) said "xin chào các bạn" at 1.0–1.4, 1.4–1.9, 2.0–2.3, 2.3–2.8 s.
    func project(_ items: [Item]) -> (Project, [String: SourceTranscript]) {
        var project = Project(name: "Invariants", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: [
                "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
                "frames": .integer(600), "hasAudio": .bool(true),
            ])
        ]
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items = items
        let words = [("xin", 1.0, 1.4), ("chào", 1.4, 1.9), ("các", 2.0, 2.3), ("bạn", 2.3, 2.8)].map {
            CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2)
        }
        let transcript = SourceTranscript(
            key: "k", language: "vi", provider: [:], transcribedAt: "", phrases: [], words: words)
        return (project, ["m": transcript])
    }

    @Test("A clip edge inside a word is an error; a word edge, a plain split and sub-frame noise are not")
    func wordCuts() throws {
        // a: source 0–1.6 s (ends inside "chào"), b continues it exactly (a split) to 2.1 s (inside "các"); c starts
        // at 2.3 s (a word edge) and ends at 3.0 s (after the last word).
        let (project, transcripts) = project([
            Item(id: "a", media: "m", at: 0, duration: 48), Item(id: "b", media: "m", at: 48, duration: 15, sourceIn: 48),
            Item(id: "c", media: "m", at: 63, duration: 21, sourceIn: 69),
        ])
        let issues = TimelineReview.wordCutIssues(project, transcripts: transcripts)
        #expect(issues.map(\.id) == ["cut-in-word-b-out"])
        #expect(issues.first?.severity == .error && issues.first?.detail.contains("“các”") == true)
        let (cut, _) = self.project([Item(id: "x", media: "m", at: 0, duration: 30, sourceIn: 36)])
        let found = TimelineReview.wordCutIssues(cut, transcripts: transcripts)
        #expect(found.map(\.id) == ["cut-in-word-x-in", "cut-in-word-x-out"])
        #expect(found[0].detail.contains("0.20 s into “xin”"))
        let full = TimelineReview.run(cut, context: { var context = ReviewContext(); context.transcripts = transcripts; return context }())
        #expect(full.filter { $0.severity == .error }.map(\.id) == ["cut-in-word-x-in", "cut-in-word-x-out"])
    }

    @Test("Characters a font cannot draw are an error, once per font and set of characters")
    func glyphs() {
        var (project, _) = project([Item(id: "a", media: "m", at: 0, duration: 60)])
        var title = Item(id: "t1", at: 0, duration: 30)
        title["text"] = .string("Xin chào")
        var second = Item(id: "t2", at: 30, duration: 30)
        second["text"] = .string("chào bạn")
        project.tracks.insert(Track(id: "titles", kind: TrackKind.text, role: "titles"), at: 0)
        project.tracks[0].items = [title, second]
        let issues = TimelineReview.glyphIssues(project) { item in
            item.text.contains("à") ? (font: "Plain", characters: "à") : nil
        }
        #expect(issues.map(\.id) == ["glyph-t1"] && issues[0].severity == .error)
    }

    @Test("A fresh project reports only invariant errors; text overlap and recognition loops are notes")
    func onlyInvariants() {
        var (project, _) = project([Item(id: "a", media: "m", at: 0, duration: 60), Item(id: "b", media: "m", at: 90, duration: 30)])
        var caption = Item(id: "loop", at: 0, duration: 400)
        caption["text"] = .string("à à à à à")
        let captions = project.tracks.firstIndex { $0.role == TrackRole.captions }!
        project.tracks[captions].items = [caption]
        let issues = TimelineReview.run(project)
        // The 400-frame caption also runs past Main's end.
        #expect(issues.filter { $0.severity == .error }.map(\.id) == ["gap-b", "gap-end"])
        #expect(issues.first { $0.id == "loop-loop" }?.severity == .info)
        #expect(!issues.contains { $0.severity == .warning })
    }

    @Test("Accepted warnings keep their reason and leave the counts; errors are never accepted; blockExport names prefixes")
    func accepted() {
        var (project, _) = project([Item(id: "a", media: "m", at: 0, duration: 60), Item(id: "b", media: "m", at: 90, duration: 30)])
        project["review"] = .object([
            "severities": .object(["framing": .string("warning")]),
            "accepted": .object([
                "gap-b": .object(["reason": .string("on purpose")]),
            ]),
            "blockExport": .array([.string("gap"), .string("glyph")]),
        ])
        var shot = Item(id: "c", media: "m", at: 120, duration: 30, sourceIn: 300)
        project.tracks[project.tracks.firstIndex { $0.id == "v1" }!].items.append(shot)
        shot.at = 150
        let issues = TimelineReview.run(project)
        #expect(issues.first { $0.id == "gap-b" }?.accepted == nil)
        project["review"] = .object([
            "severities": .object(["framing": .string("warning")]),
            "accepted": .object(["framing-c": .object(["reason": .string("same angle on purpose")])]),
            "blockExport": .array([.string("gap")]),
        ])
        let kept = TimelineReview.run(project)
        let framing = kept.first { $0.id == "framing-c" }
        #expect(framing?.accepted == "same angle on purpose")
        #expect(framing?.json.object["accepted"]?.object["reason"] == .string("same angle on purpose"))
        let summary = ReviewSummary(kept)
        #expect(summary.accepted == 1 && summary.warnings == kept.filter { $0.severity == .warning }.count - 1)
        #expect(summary.errors == 1)
        #expect(TimelineReview.blockingExport(project, issues: kept).map(\.id) == ["gap-b"])
        var bad = project
        bad["review"] = .object(["accepted": .object(["x": .object([:])])])
        #expect(throws: ProjectError.self) { try bad.validate() }
    }

    @Test("IDs anchored to clips survive a ripple elsewhere; a round diff says fixed, new and persisting")
    func rounds() {
        let issue = { (id: String) in ReviewIssue(id: id, title: id, detail: "", frame: 0) }
        let diff = ReviewRounds.diff(before: [issue("a"), issue("b")], after: [issue("b"), issue("c")]).object
        #expect(diff["fixed"]?.array.map { $0.object["id"] } == [.string("a")])
        #expect(diff["new"]?.array.map { $0.object["id"] } == [.string("c")])
        #expect(diff["persisting"]?.array.map { $0.object["id"] } == [.string("b")])
        var (project, _) = project([Item(id: "a", media: "m", at: 0, duration: 60), Item(id: "b", media: "m", at: 60, duration: 60)])
        #expect(TimelineReview.anchor(project, frame: 75) == "b+15")
        let main = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[main].items = [Item(id: "a", media: "m", at: 0, duration: 90), Item(id: "b", media: "m", at: 90, duration: 60)]
        #expect(TimelineReview.anchor(project, frame: 105) == "b+15")
        #expect(TimelineReview.anchor(project, frame: 400) == "400")
    }
}

/// Select by quote (P1-D7).
struct QuoteRangeTests {
    let transcript = SourceTranscript(
        key: "k", language: "vi", provider: [:], transcribedAt: "",
        phrases: [SubRip.Cue(start: 1.0, end: 1.9, text: "xin chào"), SubRip.Cue(start: 2.0, end: 3.4, text: "các bạn ơi giá năm chục")],
        words: [("xin", 1.0, 1.4), ("chào", 1.4, 1.9), ("các", 2.0, 2.3), ("bạn", 2.3, 2.6), ("ơi", 2.6, 2.8),
                ("giá", 2.8, 3.0), ("năm", 3.0, 3.2), ("chục", 3.2, 3.4)].map {
            CaptionWords.Timed(text: $0.0, start: $0.1, end: $0.2)
        })
    let media = Media(fields: [
        "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
        "frames": .integer(300),
    ])

    @Test("A quote resolves to word edges with sentence flags and boundaries; rough times snap outwards")
    func resolve() throws {
        let found = QuoteRange.find("giá năm chục", in: transcript.words)
        #expect(found.count == 1 && found[0].first == 5 && found[0].last == 7)
        let json = try QuoteRange.json(transcript, media: media, first: 5, last: 7).object
        #expect(json["from"] == .number(2.8) && json["to"] == .number(3.4) && json["inFrame"] == .integer(84))
        let start = try #require(json["in"]).object
        #expect(start["midWord"] == .bool(false) && start["midSentence"] == .bool(true))
        #expect(start["sentenceEdgeBefore"] == .number(2.0) && start["sentenceEdgeAfter"] == .null)
        #expect(json["out"]?.object["midSentence"] == .bool(false))
        let rough = try QuoteRange.json(transcript, media: media, from: 1.5, to: 2.4).object
        #expect(rough["from"] == .number(1.4) && rough["to"] == .number(2.6))
        #expect(rough["snap"]?.object["inDelta"] == .number(-0.1) && rough["text"] == .string("chào các bạn"))
        #expect(throws: ProjectError.self) { try QuoteRange.json(transcript, media: media, first: 7, last: 2) }
    }

    @Test("Equal matches are all returned in order; a quote that is not there finds nothing")
    func find() {
        let words = ["a", "b", "x", "a", "b"].enumerated().map { CaptionWords.Timed(text: $1, start: Double($0), end: Double($0) + 0.5) }
        #expect(QuoteRange.find("a b", in: words).map(\.first) == [0, 3])
        #expect(QuoteRange.find("q r", in: words).isEmpty)
    }
}
