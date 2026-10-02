import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
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
}
