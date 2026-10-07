import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// Credits, AI disclosure and rights flags from media licences and provenance (P2-H9).
@Suite("Project credits")
struct ProjectCreditsTests {
    private func media(_ id: String, kind: String = "video", license: String? = nil, provenance: [String: JSONValue] = [:]) -> Media {
        var media = ProjectFixtures.media(id, path: "\(id).mov", frames: 600, fps: FrameRate(30, 1), kind: kind, hasAudio: kind == "audio")
        if let license { media.fields["license"] = .string(license) }
        if !provenance.isEmpty { media.fields["provenance"] = .object(provenance) }
        return media
    }

    /// Own footage 0–90, an AI clip on top 30–60, CC-BY music, NC sticker, unknown stock clip; `unused` is not placed.
    private func project() throws -> Project {
        try Project(name: "Credits", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media("own", provenance: ["origin": .string("own")])),
            .addMedia(media("gen", provenance: ["origin": .string("ai"), "provider": .string("acme")])),
            .addMedia(media("song", kind: "audio", license: "CC-BY 4.0", provenance: [
                "origin": .string("stock"), "author": .string("Band"), "sourceUrl": .string("https://music/1"),
            ])),
            .addMedia(media("nc", license: "CC BY-NC 4.0")),
            .addMedia(media("mystery", provenance: ["origin": .string("stock")])),
            .addMedia(media("unused", license: "All rights reserved")),
            .insert(track: "v1", item: Item(id: "a", media: "own", at: 0, duration: 90)),
            .insert(track: "v2", item: Item(id: "b", media: "gen", at: 30, duration: 30)),
            .insert(track: "v2", item: Item(id: "c", media: "nc", at: 60, duration: 10)),
            .insert(track: "v2", item: Item(id: "d", media: "mystery", at: 70, duration: 10)),
            .insert(track: "a1", item: Item(id: "m", media: "song", at: 0, duration: 90)),
        ])).project
    }

    @Test("Raw rights facts come from the media the edit plays")
    func credits() throws {
        let credits = ProjectCredits.of(try project())
        #expect(credits.entries.map(\.media) == ["own", "gen", "nc", "mystery", "song"])
        #expect(credits.entries.first { $0.media == "song" }?.license == .string("CC-BY 4.0"))
        #expect(credits.entries.first { $0.media == "gen" }?.framesOnTop == 30)
        #expect(credits.aiMedia == ["gen"] && abs(credits.aiPictureShare - 30.0 / 90.0) < 0.001)
        #expect(credits.json.object["ai"]?.object["pictureShare"] == .number(0.333))
    }

    @Test("Review is silent about rights by default; with review.credits it notes AI picture")
    func review() throws {
        var project = try project()
        #expect(TimelineReview.rightsIssues(project, context: ReviewContext()).isEmpty)
        project = try project.applying(.setProjectProperties(patch: ["review": .object(["credits": .bool(true)])])).project
        #expect(throws: ProjectError.self) {
            try project.applying(.setProjectProperties(patch: ["review": .object(["credits": .string("yes")])]))
        }
        let issues = TimelineReview.rightsIssues(project, context: ReviewContext())
        #expect(issues.map(\.id) == ["ai-media"] && issues[0].detail.contains("33%"))

        let plain = try Project(name: "Plain", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media("clip")), .insert(track: "v1", item: Item(id: "a", media: "clip", at: 0, duration: 30)),
        ])).project
        let plainOn = try plain.applying(.setProjectProperties(patch: ["review": .object(["credits": .bool(true)])])).project
        #expect(TimelineReview.rightsIssues(plainOn, context: ReviewContext()).isEmpty)
        #expect(ProjectCredits.of(plain).aiPictureShare == 0)
    }
}
