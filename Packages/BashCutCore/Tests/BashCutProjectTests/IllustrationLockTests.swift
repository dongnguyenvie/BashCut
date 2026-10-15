import Foundation
import Testing

@testable import BashCutProject

@Suite("Illustration style lock and the disclosure of generated pictures (#550)")
struct IllustrationLockTests {
    private let lock: JSONValue = .object([
        "style": .string("crayon on paper"), "references": .array([.string("refs/hero.png"), .string("project:owl")]),
        "seed": .integer(42), "disclosure": .string("Ảnh tạo bằng AI"),
    ])

    @Test("A lock round-trips; unknown keys, long texts, bad seeds and too many references are refused")
    func validation() throws {
        let parsed = try IllustrationLock(lock)
        #expect(parsed.style == "crayon on paper" && parsed.references.count == 2 && parsed.seed == 42)
        #expect(parsed.json == lock)
        #expect(IllustrationLock().isEmpty)
        for bad: JSONValue in [
            .string("crayon"), .object(["model": .string("x")]), .object(["seed": .integer(-1)]),
            .object(["style": .string(String(repeating: "x", count: 4_001))]),
            .object(["references": .array(Array(repeating: .string("a.png"), count: 9))]),
            .object(["disclosure": .string("")]),
        ] {
            #expect(throws: ProjectError.self) { try IllustrationLock(bad) }
        }
    }

    @Test("The project's lock wins over the brand's; a kit may hold only a lock; bad locks fail validation")
    func source() throws {
        var project = Project(name: "Lock", fps: FrameRate(30, 1))
        #expect(project.illustration == nil && project.disclosureText == nil)
        try LibraryItem(id: "kit", kind: .brand, name: "Kit", params: ["illustration": lock]).validate()
        project = try project.applying(.setProjectProperties(patch: [
            "brand": .object(["illustration": .object(["style": .string("engraving")]), "disclosure": .string("AI")]),
        ])).project
        #expect(project.illustration?.source == "brand" && project.illustration?.lock.style == "engraving")
        #expect(project.disclosureText == "AI")
        project = try project.applying(.setProjectProperties(patch: ["illustration": lock])).project
        #expect(project.illustration?.source == "project" && project.disclosureText == "Ảnh tạo bằng AI")
        #expect(throws: (any Error).self) {
            try project.applying(.setProjectProperties(patch: ["illustration": .object(["seed": .string("x")])]))
        }
    }

    /// A generated picture on Main for 0..<90 and a plain one after it.
    private func project(labels: [Item], credits: Bool = true) throws -> Project {
        let base = Project(name: "Disclose", fps: FrameRate(30, 1))
        let main = try #require(base.tracks.first { $0.role == TrackRole.main }).id
        let captions = try base.requireTrack(role: TrackRole.captions).id
        var generated = Media(fields: [
            "id": .string("gen"), "path": .string("generated/images/a/1.png"), "kind": .string("image"),
            "fps": FrameRate(30, 1).json, "frames": .integer(300), "hasAudio": .bool(false),
        ])
        generated["generated"] = .bool(true)
        let plain = Media(fields: [
            "id": .string("photo"), "path": .string("photo.png"), "kind": .string("image"),
            "fps": FrameRate(30, 1).json, "frames": .integer(300), "hasAudio": .bool(false),
        ])
        var ops: [EditOperation] = [
            .setProjectProperties(patch: [
                "brand": .object(["disclosure": .string("Ảnh tạo bằng AI")]),
                "review": .object(["credits": .bool(credits)]),
            ]),
            .addMedia(generated), .addMedia(plain),
            .insert(track: main, item: Item(id: "scene", media: "gen", at: 0, duration: 90)),
            .insert(track: main, item: Item(id: "real", media: "photo", at: 90, duration: 90)),
        ]
        ops += labels.map { .insert(track: captions, item: $0) }
        return try base.applying(.group(label: "Setup", author: .user, ops: ops)).project
    }

    private func label(_ at: Int, _ duration: Int, text: String = "Ảnh tạo bằng AI", flag: Bool = false) -> Item {
        var item = Item(at: at, duration: duration)
        item["text"] = .string(text)
        if flag { item["disclosure"] = .bool(true) }
        return item
    }

    @Test("Review flags a generated picture until labels cover all of it, only with review.credits on")
    func review() throws {
        #expect(TimelineReview.disclosureIssues(try project(labels: [], credits: false)).isEmpty)
        let bare = TimelineReview.disclosureIssues(try project(labels: []))
        #expect(bare.map(\.id) == ["ai-undisclosed-scene"] && bare.first?.fix?.command == "image.disclose")
        #expect(bare.first?.facts["uncoveredFrames"] == .integer(90))
        let half = TimelineReview.disclosureIssues(try project(labels: [label(0, 45)]))
        #expect(half.first?.facts["uncoveredFrames"] == .integer(45))
        #expect(TimelineReview.disclosureIssues(try project(labels: [label(0, 45), label(45, 60, text: "x", flag: true)])).isEmpty)
        #expect(ReviewIssue.kind(of: "ai-undisclosed-scene") == "ai-undisclosed")
        #expect(TimelineReview.uncoveredFrames(10..<20, by: [0..<12, 15..<16, 18..<40]) == 5)
    }
}
