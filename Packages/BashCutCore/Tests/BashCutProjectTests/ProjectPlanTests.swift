import Foundation
import Testing

@testable import BashCutProject

/// The brief and the edit plan as project data (P1-D1, P1-D2).
struct ProjectPlanTests {
    let brief: JSONValue = .object([
        "goal": .object(["value": .string("Food tour"), "status": .string("stated")]),
        "lengthSeconds": .object(["value": .object(["min": .number(30), "max": .number(45)]), "status": .string("inferred")]),
        "outputs": .object(["value": .array([.string("tiktok")]), "status": .string("confirmed"), "source": .string("chat")]),
        "ideas": .array([.object(["text": .string("open on the stall")])]),
    ])
    let plan: JSONValue = .object([
        "mode": .string("create"), "stage": .string("draft"),
        "sections": .array([
            .object(["id": .string("hook"), "label": .string("Hook"),
                     "lengthSeconds": .object(["min": .number(1), "max": .number(3)]), "frozen": .bool(true)]),
            .object(["id": .string("body"), "label": .string("B")]),
        ]),
        "shots": .array([.object(["id": .string("s1"), "purpose": .string("open"), "size": .string("CU"),
                                 "source": .string("footage"), "mustShow": .array([.string("bánh mì")])])]),
        "beats": .array([.object(["id": .string("b1"), "section": .string("hook"), "text": .string("Ăn gì?")])]),
        "ranges": .object(["maxShotSeconds": .object(["min": .number(2), "max": .number(4), "reason": .string("fast")])]),
    ])

    @Test("Brief and plan are free JSON: unknown fields load, validate and save")
    func freeNotes() throws {
        var project = ReviewSequenceTests().project()
        project["brief"] = .object(["tone": .string("warm"), "goal": .string("x")])
        project["plan"] = .object(["mode": .string("auto"), "anything": .array([.integer(1)])])
        try project.validate()
        #expect(throws: ProjectError.self) { try ProjectPlan.validateNotes(.array([]), key: "brief") }
        #expect(ProjectPlan.range(.object(["min": .number(1), "max": .number(2)]))?.max == 2)
        #expect(ProjectPlan.strings(.array([.string("tiktok")])) == ["tiktok"])
    }

    @Test("Review compares the brief's length and outputs and each planned section with what was cut, as info")
    func review() throws {
        var project = ReviewSequenceTests().project()
        project["brief"] = brief
        project["plan"] = plan
        project.markers = [TimelineMarker(at: 0, kind: "section", label: "Hook"), TimelineMarker(at: 120, kind: "section", label: "B")]
        let issues = TimelineReview.planIssues(project)
        let byID = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        #expect(issues.allSatisfy { $0.severity == .info })
        #expect(byID["brief-length"]?.detail.contains("7.0 s") == true)
        #expect(byID["brief-outputs"]?.fix?.command == "project.format")
        #expect(byID["plan-section-hook"]?.detail == "Planned 1–3 s, measured 4.0 s.")
        #expect(byID["plan-section-body"] == nil)
    }

    @Test("The summary names the brief's goal, outputs and length and counts the plan")
    func summary() {
        var project = Project(name: "Plan", fps: FrameRate(30, 1))
        #expect(ProjectPlan.summary(project) == .object([:]))
        project["brief"] = brief
        project["plan"] = plan
        let json = ProjectPlan.summary(project).object
        #expect(json["brief"]?.object.keys.sorted() == ["goal", "lengthSeconds", "outputs"])
        let row = json["plan"]?.object ?? [:]
        #expect(row["sections"] == .integer(2) && row["shots"] == .integer(1) && row["beats"] == .integer(1))
        #expect(row["mode"] == .string("create") && row["frozen"] == .array([.string("hook")]))
    }
}

/// The plan against what was measured (P1-D3).
struct PlanCoverageTests {
    @Test("Each clip says which described shot it plays and its planShot; no plan matching")
    func coverage() throws {
        var project = ReviewSequenceTests().project()
        let main = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[main].items[2]["planShot"] = .string("tagged")
        let json = PlanCoverage.coverage(project).object
        let clips = (json["clips"]?.array ?? []).map(\.object)
        #expect(clips.map { $0["item"] } == ["a", "b", "c", "d"].map(JSONValue.string))
        #expect(clips[0]["described"]?.object["index"] == .integer(0) && clips[0]["described"]?.object["size"] == .string("MS"))
        #expect(clips[2]["planShot"] == .string("tagged") && clips[2]["described"]?.object["index"] == .integer(1))
        #expect(clips[3]["described"]?.object["size"] == .string("CU"))
        #expect(json["summary"]?.object["described"] == .integer(4))
        #expect(json["shots"] == nil)
    }

    @Test("Beats are found in the heard words with their share, place and section against the plan")
    func script() throws {
        var project = ReviewSequenceTests().project()
        project["plan"] = .object([
            "sections": .array([.object(["id": .string("b"), "label": .string("B")])]),
            "beats": .array([
                .object(["id": .string("1"), "text": .string("xin chào các bạn"), "section": .string("b")]),
                .object(["id": .string("2"), "text": .string("hôm nay ăn phở")]),
            ]),
        ])
        let words = ["xin", "chào", "mọi", "bạn"].enumerated().map { index, text in
            ReviewSync.WordSpan(at: 120 + index * 10, end: 128 + index * 10, text: text)
        }
        let json = PlanCoverage.scriptCheck(project, words: words).object
        let beats = (json["beats"]?.array ?? []).map(\.object)
        #expect(beats[0]["heardShare"] == .number(0.75) && beats[0]["at"] == .integer(120))
        #expect(beats[0]["inPlannedSection"] == .bool(true) && beats[0]["unmatched"] == .array([.string("các")]))
        #expect(beats[1]["heardShare"] == .number(0) && beats[1]["at"] == nil)
        let given = PlanCoverage.scriptCheck(project, words: words, beats: [["id": .string("x"), "text": .string("xin chào")]]).object
        #expect(given["beats"]?.array.first?.object["heardShare"] == .number(1))
    }
}

/// The selects store (P1-D8).
struct ProjectSelectsTests {
    @Test("Selects validate their shape; a must-keep select no clip plays is a warning")
    func selects() throws {
        var project = ReviewSequenceTests().project()
        let select = { (id: String, from: Double, to: Double, mustKeep: Bool) -> JSONValue in
            .object([
                "id": .string(id), "media": .string("m"), "from": .number(from), "to": .number(to),
                "status": .string("kept"), "mustKeep": .bool(mustKeep), "quote": .string("giá năm chục"),
            ])
        }
        // Clips play source 0–4 s, 9–10 s and 14–16 s.
        project["selects"] = .array([select("played", 1, 2, true), select("missing", 5, 6, true), select("free", 5, 6, false)])
        try project.validate()
        #expect(project.selects.map(\.id) == ["played", "missing", "free"])
        let issues = TimelineReview.mustKeepIssues(project)
        #expect(issues.map(\.id) == ["must-keep-missing"] && issues[0].severity == .warning)
        #expect(issues[0].detail.contains("giá năm chục"))
        for bad: JSONValue in [
            .array([select("a", 2, 1, false)]),
            .array([select("a", 1, 2, false), select("a", 3, 4, false)]),
            .array([.object(["id": .string("x"), "media": .string("m"), "from": .number(0), "to": .number(1), "status": .string("")])]),
        ] {
            var copy = project
            copy["selects"] = bad
            #expect(throws: ProjectError.self) { try copy.validate() }
        }
    }

    @Test("Marking keeps the pick's reason, records why the status changed and drops that note on the next change")
    func marking() throws {
        var project = ReviewSequenceTests().project()
        project["selects"] = .array([.object([
            "id": .string("s"), "media": .string("m"), "from": .number(1), "to": .number(2), "status": .string("candidate"),
            "reason": .string("states the topic"),
        ])])
        project["selects"] = .array(try project.markingSelects(["s"], status: "rejected", mustKeep: nil, reason: "too generic")
            .map(JSONValue.object))
        #expect(project.selects[0].reason == "states the topic" && project.selects[0].statusReason == "too generic")
        project["selects"] = .array(try project.markingSelects(["s"], status: "kept", mustKeep: true, reason: nil)
            .map(JSONValue.object))
        #expect(project.selects[0].status == "kept" && project.selects[0].mustKeep && project.selects[0].statusReason == nil)
        #expect(throws: ProjectError.self) { try project.markingSelects(["nope"], status: "kept", mustKeep: nil, reason: nil) }
    }

    @Test("A select of sound-only media goes on the dialogue layer, pictures on Main")
    func placementLayer() throws {
        var project = ReviewSequenceTests().project()
        let audio = Media(fields: ["id": .string("pod"), "path": .string("pod.m4a"), "kind": .string("audio"),
                                   "fps": FrameRate(48_000, 1).json, "frames": .integer(480_000)])
        project.media.append(audio)
        #expect(try project.selectTrackID(for: project.media[0]) == project.track(role: TrackRole.main, kind: "video")?.id)
        let dialogue = try #require(project.track(role: TrackRole.dialogue, kind: "audio"))
        #expect(try project.selectTrackID(for: audio) == dialogue.id)
        project.tracks.removeAll { $0.id == dialogue.id }
        #expect(try project.selectTrackID(for: audio) == project.track(role: TrackRole.music)?.id)
    }
}

/// Derived projects and variants (P1-D9).
struct ProjectDerivationTests {
    @Test("A derived project keeps format, outputs and profile, plays only the select's range and says where it came from")
    func derive() throws {
        var project = ReviewSequenceTests().project()
        project["output"] = .object(["presets": .array([.string("tiktok")])])
        project["review"] = .object(["maxShotSeconds": .number(4)])
        let root = URL(fileURLWithPath: "/tmp/long")
        let select = ProjectSelect(fields: [
            "id": .string("s1"), "media": .string("m"), "from": .number(2), "to": .number(5), "status": .string("kept"),
        ])
        let derived = try ProjectDerivation.derived(
            from: project,
            target: .init(root: root, path: "/tmp/long/project.bashcut.json", destination: URL(fileURLWithPath: "/tmp/long-s1"), name: "Short"),
            select: select)
        try derived.validate()
        #expect(derived.revision == 0 && derived["id"] != project["id"] && derived.name == "Short")
        #expect(derived.media.map(\.path) == ["../long/m.mp4"])
        let clips = derived.tracks.first { $0.id == "v1" }?.items ?? []
        #expect(clips.count == 1 && clips[0].sourceIn == 60 && clips[0].duration == 90)
        #expect(derived["output"] == project["output"] && derived["review"] == project["review"])
        #expect(derived["derivedFrom"]?.object["select"] == .string("s1"))
        #expect(derived.markers.isEmpty && derived["selects"] == nil)

        project.media.append(Media(fields: ["id": .string("pod"), "path": .string("pod.m4a"), "kind": .string("audio"),
                                            "fps": FrameRate(48_000, 1).json, "frames": .integer(480_000)]))
        let audio = try ProjectDerivation.derived(
            from: project,
            target: .init(root: root, path: "/tmp/long/project.bashcut.json", destination: URL(fileURLWithPath: "/tmp/long-s2"), name: "Pod"),
            select: ProjectSelect(fields: ["id": .string("s2"), "media": .string("pod"), "from": .number(1), "to": .number(3)]))
        let dialogue = audio.track(role: TrackRole.dialogue, kind: "audio")
        #expect(dialogue?.items.count == 1 && audio.tracks.first { $0.id == "v1" }?.items.isEmpty == true)
    }

    @Test("A variant is a full copy that records its change; diff lists fields and items that differ")
    func variants() throws {
        let project = ReviewSequenceTests().project()
        var variant = ProjectDerivation.variant(
            of: project,
            target: .init(root: URL(fileURLWithPath: "/tmp/ad"), path: "/tmp/ad/project.bashcut.json",
                          destination: URL(fileURLWithPath: "/tmp/ads/ad-b"), name: "B"),
            changed: "hook")
        #expect(variant.media.map(\.path) == ["../../ad/m.mp4"])
        try variant.validate()
        #expect(variant["variant"]?.object["changed"] == .string("hook") && variant.tracks == project.tracks)
        let main = variant.tracks.firstIndex { $0.id == "v1" }!
        variant.tracks[main].items.removeFirst()
        variant["review"] = .object(["hookSeconds": .number(2)])
        let diff = ProjectDerivation.diff(project, variant).object
        #expect(diff["fields"]?.array.contains(.string("review")) == true)
        #expect(diff["fields"]?.array.contains(.string("media")) == true)
        // With each folder, the rewritten relative paths name the same file.
        let resolved = ProjectDerivation.diff(
            project, variant, leftRoot: URL(fileURLWithPath: "/tmp/ad"), rightRoot: URL(fileURLWithPath: "/tmp/ads/ad-b")).object
        #expect(resolved["fields"] == .array([.string("review")]))
        #expect(diff["items"]?.object["removed"] == .array([.string("a")]))
        #expect(diff["changedAs"]?.object["right"] == .string("hook"))
    }
}

/// Bounded change digests on edit results (P2-G1).
struct ChangeDigestTests {
    @Test("Added, removed and modified items with their fields, project fields, limits and + ~ - lines")
    func digest() {
        let before = ReviewSequenceTests().project()
        var after = before
        let main = after.tracks.firstIndex { $0.id == "v1" }!
        after.tracks[main].items.removeFirst()
        after.tracks[main].items[0].at = 0
        after.tracks[main].items.append(Item(id: "e", media: "m", at: 300, duration: 30))
        after["review"] = .object(["hookSeconds": .number(2)])
        let json = ChangeDigest.json(before: before, after: after, limit: 1).object
        #expect(json["removed"] == .array([.string("a")]))
        #expect(json["modified"]?.array.first?.object["fields"] == .array([.string("at")]))
        #expect(json["project"] == .array([.string("review")]))
        #expect(json["counts"]?.object["added"] == .integer(1) && json["truncated"] == .bool(false))
        #expect(json["text"]?.string?.contains("+ e on v1") == true && json["text"]?.string?.contains("- a") == true)
    }
}
