import Foundation
import Testing

@testable import BashCutProject

struct SourceEditingTests {
    private func fixture() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("source.mov"),
            "frames": .integer(600), "fps": FrameRate(60, 1).json,
        ])
        return try Project(name: "Source edits", fps: FrameRate(30, 1)).applying(
            .group(
                label: "Setup", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(id: "first", media: "m", at: 0, duration: 60)),
                    .insert(
                        track: "v1", item: Item(id: "second", media: "m", at: 60, duration: 60, sourceIn: 120)),
                ])
        ).project
    }
    @Test("Insert at playhead splits a clip, shifts later clips and maps source FPS")
    func insert() throws {
        let project = try fixture()
        let operation = try project.sourceEdit(
            mediaID: "m", sourceRange: 10..<50,
            at: 30, trackID: "v1", mode: .insert, itemID: "inserted")
        let result = try project.applying(operation)
        let items = result.project.tracks[0].items.sorted { $0.at < $1.at }
        #expect(items.map(\.at) == [0, 30, 50, 80])
        #expect(items.map(\.duration) == [30, 20, 30, 60])
        #expect(items.map(\.sourceIn) == [0, 10, 60, 120])
        #expect(result.project.duration == 140)
        var restored = try result.project.applying(result.inverse).project
        restored.revision = project.revision
        #expect(restored == project)
    }
    @Test("Overwrite preserves material outside both boundaries without shifting later clips")
    func overwrite() throws {
        let project = try fixture()
        let operation = try project.sourceEdit(
            mediaID: "m", sourceRange: 300..<380,
            at: 40, trackID: "v1", mode: .overwrite, itemID: "inserted")
        let result = try project.applying(operation).project
        let items = result.tracks[0].items.sorted { $0.at < $1.at }
        #expect(items.map(\.id) == ["first", "inserted", "second"])
        #expect(items.map(\.at) == [0, 40, 80])
        #expect(items.map(\.duration) == [40, 40, 40])
        #expect(items.map(\.sourceIn) == [0, 300, 160])
        #expect(result.duration == project.duration)
    }
    @Test("Overwrite inside one clip keeps both remnants and unknown properties")
    func innerOverwrite() throws {
        var project = try fixture()
        project.tracks[0].items[0]["future"] = .string("preserved")
        let operation = try project.sourceEdit(
            mediaID: "m", sourceRange: 400..<420,
            at: 10, trackID: "v1", mode: .overwrite)
        let items = try project.applying(operation).project.tracks[0].items.sorted { $0.at < $1.at }
        #expect(items.map(\.at) == [0, 10, 20, 60])
        #expect(items[2].sourceIn == 40)
        #expect(items[0]["future"] == .string("preserved"))
        #expect(items[2]["future"] == .string("preserved"))
    }
    @Test("Invalid and sub-frame source ranges fail before applying")
    func invalidRanges() throws {
        let project = try fixture()
        for (start, end) in [(-1, 20), (20, 20), (0, 601), (0, 1)] {
            #expect(throws: ProjectError.self) {
                try project.sourceEdit(
                    mediaID: "m", sourceRange: start..<end, at: 0, trackID: "v1", mode: .insert)
            }
        }
    }
}
