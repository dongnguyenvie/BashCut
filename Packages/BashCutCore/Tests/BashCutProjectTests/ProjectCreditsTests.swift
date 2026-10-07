import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// Credits, AI disclosure and rights flags from media licences and provenance (P2-H9).
@Suite("Project credits")
struct ProjectCreditsTests {
    private func media(_ id: String, kind: String = "video", license: String? = nil, provenance: [String: JSONValue] = [:]) -> Media {
        var media = ProjectFixtures.media(id, path: "\(id).mov", frames: 600, fps: FrameRate(30, 1), kind: kind, hasAudio: kind == "audio")
        if let license { media.fields["license"] = LicenseTerms.parse(license).json }
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

    @Test("Credit lines, AI share and disclosures, Content ID and flags come from the media the edit plays")
    func credits() throws {
        let project = try project()
        let tiktok = try #require(OutputPlatform.named("tiktok"))
        let credits = ProjectCredits.of(project, platforms: [tiktok])
        // CC BY and CC BY-NC both ask for credit; the own, AI and unknown media have no line.
        #expect(Set(credits.lines.map(\.media)) == ["song", "nc"] && credits.lines.allSatisfy(\.required))
        #expect(credits.lines.first { $0.media == "song" }?.text == "“song” by Band — CC-BY 4.0 — https://music/1")
        #expect(credits.lines.first { $0.media == "nc" }?.text == "“nc” — CC BY-NC 4.0")
        #expect(credits.text.components(separatedBy: "\n").count == 2)
        #expect(credits.aiMedia == ["gen"] && abs(credits.aiPictureShare - 30.0 / 90.0) < 0.001)
        #expect(credits.disclosures.map(\.platform) == ["tiktok"])
        #expect(credits.contentIDNotes.count == 1 && credits.contentIDNotes[0].hasPrefix("song"))
        #expect(credits.nonCommercial == ["nc"] && credits.unknown == ["mystery"] && credits.allRightsReserved.isEmpty)
        #expect(credits.json.object["ai"]?.object["pictureShare"] == .number(0.333))
    }

    @Test("Review is silent about rights by default; with review.credits it notes AI use, credits and unclear rights")
    func review() throws {
        var context = ReviewContext()
        context.targets.platforms = [try #require(OutputPlatform.named("youtube"))]
        var project = try project()
        #expect(TimelineReview.rightsIssues(project, context: context).isEmpty)
        project = try project.applying(.setProjectProperties(patch: ["review": .object(["credits": .bool(true)])])).project
        #expect(throws: ProjectError.self) {
            try project.applying(.setProjectProperties(patch: ["review": .object(["credits": .string("yes")])]))
        }
        let issues = TimelineReview.rightsIssues(project, context: context)
        #expect(issues.map(\.id) == ["ai-disclosure", "credits-required", "rights-unclear"])
        #expect(issues.allSatisfy { $0.severity == .info })
        #expect(issues[0].detail.contains("33%") && issues[0].detail.contains("youtube"))
        #expect(issues[2].detail.contains("non-commercial licence: nc") && issues[2].detail.contains("licence unknown: mystery"))

        let plain = try Project(name: "Plain", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media("clip")), .insert(track: "v1", item: Item(id: "a", media: "clip", at: 0, duration: 30)),
        ])).project
        let plainOn = try plain.applying(.setProjectProperties(patch: ["review": .object(["credits": .bool(true)])])).project
        #expect(TimelineReview.rightsIssues(plainOn, context: ReviewContext()).isEmpty)
        #expect(ProjectCredits.of(plain).lines.isEmpty && ProjectCredits.of(plain).aiPictureShare == 0)
    }
}
