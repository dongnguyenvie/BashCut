import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing

@testable import BashCutEngine

/// Media frame counts come from the file's duration, which can run past the last picture (audio longer than video,
/// or a frame rate rounded at import). A clip that uses those frames must hold the last picture, not fail export.
struct SourceEndTests {
    @Test("Clips that run past the last source picture export by holding it, transition holds included")
    func clipPastSourceEnd() async throws {
        let root = try await TestFixtures.requireMediaRoot()
        // The fixture has 60 pictures; claim 66 as a longer container duration would.
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(66),
        ])
        let project = try Project(name: "Source end").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media),
                .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 30, sourceIn: 36)),
                .insert(track: "v1", item: Item(id: "b", media: "m", at: 30, duration: 66)),
                .upsertTransition(id: "cut", kind: "dissolve", from: "a", to: "b", duration: 6),
            ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let directory = try TestFixtures.temporaryDirectory("source-end")
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("export.mp4")
        try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        let duration = try await AVURLAsset(url: output).load(.duration)
        #expect(abs(duration.seconds - Double(project.duration) / project.fps.value) < 0.1)
    }
}
