import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct CompositionStructureTests {
    @Test("Look edits keep the composition structure; timing edits change it")
    func structure() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59),
        ])
        let base = try Project(name: "Structure").applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59)),
        ])).project
        let builder = CompositionBuilder(source: OriginalMediaSource())
        let root = video.deletingLastPathComponent()
        func structure(_ project: Project) async throws -> Int? {
            try await builder.build(project, root: root, purpose: .preview).structure
        }
        let original = try #require(try await structure(base))
        #expect(try await structure(base) == original)
        for patch: [String: JSONValue] in [
            ["opacity": .number(0.3)], ["color": .object(["exposure": .number(1)])], ["volumeDb": .number(-6)],
            ["transform": .object(["zoom": .number(1.4)])],
            ["keyframes": ItemMotion(keys: ["pan": [.init(frame: 0, value: -50), .init(frame: 50, value: 50)]]).json],
        ] {
            let edited = try base.applying(.setProperties(item: "c", patch: patch)).project
            #expect(try await structure(edited) == original, "\(patch.keys)")
        }
        let trimmed = try base.applying(.trim(item: "c", edge: .end, toFrame: 30, ripple: false)).project
        #expect(try await structure(trimmed) != original)
        let faster = try base.applying(.setSpeed(item: "c", speed: 2, keepDuration: false)).project
        #expect(try await structure(faster) != original)
    }
}
