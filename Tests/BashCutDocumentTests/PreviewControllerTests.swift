import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

private actor BuildLog {
    private(set) var builds = 0
    func built() { builds += 1 }
}

private struct CountingEngine: RenderEngine {
    let log: BuildLog

    func build(_ project: Project, root: URL, workspace: URL?, purpose: RenderPurpose) async throws
        -> CompositionSnapshot
    {
        await log.built()
        // AVPlayerItem rejects a video composition without a render size.
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: 720, height: 1280)
        video.frameDuration = CMTime(value: 1, timescale: 30)
        return CompositionSnapshot(
            composition: AVMutableComposition(), videoComposition: video, audioMix: AVMutableAudioMix())
    }

    func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        ExportReceipt(url: url, duration: 0, bytes: 0)
    }
}

@MainActor
struct PreviewControllerTests {
    private func project(frames: Int = 30) throws -> Project {
        var caption = Item(at: 0, duration: frames)
        caption["text"] = .string("Xin chào")
        let base = Project(name: "Preview")
        return try base.applying(.insert(track: base.requireTrack(role: TrackRole.captions).id, item: caption)).project
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<400 where !(await condition()) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await condition())
    }

    @Test("Seeking clamps to the last project the preview was given")
    func seekClamps() throws {
        let preview = PreviewController(engine: CountingEngine(log: BuildLog()))
        preview.rebuild(try project(frames: 30), root: nil, workspace: nil)
        preview.seek(500)
        #expect(preview.playhead == 30)
        preview.seek(-3)
        #expect(preview.playhead == 0)
        preview.seek(12)
        preview.reset(Project(name: "Next"))
        #expect(preview.playhead == 0)
    }

    @Test("A project without a folder or frames builds nothing")
    func nothingToBuild() async throws {
        let log = BuildLog()
        let preview = PreviewController(engine: CountingEngine(log: log))
        preview.rebuild(try project(), root: nil, workspace: nil)
        preview.rebuild(Project(name: "Empty"), root: FileManager.default.temporaryDirectory, workspace: nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await log.builds == 0)
        #expect(preview.snapshot == nil)
    }

    @Test("Quick successive rebuilds build once; color comparison builds the original too")
    func rebuildAndCompare() async throws {
        let log = BuildLog()
        let preview = PreviewController(engine: CountingEngine(log: log))
        let root = FileManager.default.temporaryDirectory
        let value = try project()
        preview.rebuild(value, root: root, workspace: nil)
        preview.rebuild(value, root: root, workspace: nil)
        try await waitUntil { await log.builds == 1 }
        #expect(preview.buildCount == 1)

        preview.setColorComparison(true)
        #expect(preview.showColorComparison)
        try await waitUntil { await log.builds == 3 }
        preview.reset(value)
        #expect(!preview.showColorComparison)
        #expect(preview.snapshot == nil)
    }

    @Test("Scrubbing keeps one exact seek in flight and lands on the newest frame")
    func scrubChases() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59),
        ])
        let base = Project(name: "Scrub")
        let value = try base.applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59)),
        ])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        preview.rebuild(value, root: video.deletingLastPathComponent(), workspace: nil)
        try await waitUntil { preview.snapshot != nil && preview.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: .milliseconds(100))
        let before = preview.seekCount
        for frame in stride(from: 2, through: 40, by: 2) { preview.seek(frame) }
        #expect(preview.playhead == 40)
        #expect(preview.seekCount - before <= 2)
        try await waitUntil { value.fps.frame(preview.player.currentTime()) == 40 }
        #expect(preview.seekCount - before <= 3)
    }

    @Test("An edit keeps the previous picture until the new composition is ready")
    func rebuildKeepsPicture() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59),
        ])
        let base = Project(name: "Swap")
        let first = try base.applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59)),
        ])).project
        let second = try first.applying(.setProperties(item: "c", patch: ["opacity": .number(0.5)])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        let root = video.deletingLastPathComponent()
        preview.rebuild(first, root: root, workspace: nil)
        try await waitUntil { preview.isCurrent }
        let shown = preview.player
        let composition = try #require(preview.snapshot?.composition)

        preview.rebuild(second, root: root, workspace: nil)
        #expect(!preview.isCurrent)
        #expect(preview.snapshot?.composition === composition)
        #expect(preview.player === shown && shown.currentItem != nil)
        try await waitUntil { preview.isCurrent }
        #expect(preview.snapshot?.composition !== composition)
        #expect(preview.player !== shown && shown.currentItem == nil)
        #expect(preview.player.currentItem?.status == .readyToPlay)
    }
}
