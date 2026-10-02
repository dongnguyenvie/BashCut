import Foundation
import Testing

@testable import BashCutProject

struct AdvancedTrimTests {
    private func fixture() throws -> Project {
        let asset = Media(fields: [
            "id": .string("m"), "path": .string("clip.mov"),
            "fps": FrameRate(60, 1).json, "frames": .integer(600),
        ])
        return try Project(name: "Trim", fps: FrameRate(30, 1)).applying(
            .group(
                label: "Import", author: .user,
                ops: [
                    .addMedia(asset),
                    .insert(track: "v1", item: Item(id: "left", media: "m", at: 0, duration: 60, sourceIn: 20)),
                    .insert(track: "v1", item: Item(id: "right", media: "m", at: 60, duration: 60, sourceIn: 140)),
                ])
        ).project
    }
    @Test("Rolling either side preserves runtime and maps source FPS")
    func roll() throws {
        let original = try fixture()
        for operation in [
            EditOperation.roll(item: "left", edge: .end, toFrame: 75),
            .roll(item: "right", edge: .start, toFrame: 75),
        ] {
            let result = try original.applying(operation)
            #expect(result.project.duration == 120)
            #expect(result.project.tracks[0].items[0].duration == 75)
            #expect(result.project.tracks[0].items[1].at == 75)
            #expect(result.project.tracks[0].items[1].duration == 45)
            #expect(result.project.tracks[0].items[1].sourceIn == 170)
            var restored = try result.project.applying(result.inverse).project
            restored.revision = original.revision
            #expect(restored == original)
        }
        let backwards = try original.applying(.roll(item: "left", edge: .end, toFrame: 45)).project
        #expect(backwards.tracks[0].items[1].sourceIn == 110)
    }
    @Test("Slip preserves timing and unknown fields through undo and redo")
    func slip() throws {
        var original = try fixture()
        original.tracks[0].items[0]["future"] = .string("keep")
        var history = ProjectHistory(project: original)
        try history.apply(.slip(item: "left", sourceIn: 100), label: "Slip")
        let slipped = history.project.tracks[0].items[0]
        #expect(slipped.at == 0 && slipped.duration == 60 && slipped.sourceIn == 100)
        #expect(slipped["future"] == .string("keep"))
        try history.undo()
        #expect(history.project.tracks[0].items[0] == original.tracks[0].items[0])
        try history.redo()
        #expect(history.project.tracks[0].items[0] == slipped)
    }
    @Test("Invalid roll and source overruns fail atomically")
    func invalid() throws {
        var history = ProjectHistory(project: try fixture())
        let original = history.project
        for operation in [
            EditOperation.roll(item: "left", edge: .start, toFrame: 10),
            .roll(item: "left", edge: .end, toFrame: 120),
            .slip(item: "left", sourceIn: 500), .slip(item: "left", sourceIn: -1),
        ] {
            #expect(throws: ProjectError.self) { try history.apply(operation, label: "Invalid") }
            #expect(history.project == original)
            #expect(history.undoEntries.isEmpty)
        }
        var gap = original
        gap.tracks[0].items[1].at = 70
        #expect(throws: ProjectError.self) { try gap.applying(.roll(item: "left", edge: .end, toFrame: 50)) }
    }
}
