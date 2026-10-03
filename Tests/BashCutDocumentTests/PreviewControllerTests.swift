import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

private actor BuildLog {
    private(set) var builds = 0
    private(set) var delays = 0
    func delayed() { delays += 1 }
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

    @Test("A discrete edit preempts coalescing without waiting through the debounce")
    func discretePreemptsDebounce() async throws {
        let log = BuildLog()
        let preview = PreviewController(engine: CountingEngine(log: log), coalescingDelay: {
            await log.delayed()
            try await Task.sleep(for: .seconds(30))
        })
        let value = try project()
        let root = FileManager.default.temporaryDirectory
        preview.rebuild(value, root: root, workspace: nil, coalescing: true)
        try await waitUntil { await log.delays == 1 }
        #expect(await log.builds == 0)
        preview.rebuild(value, root: root, workspace: nil)
        try await waitUntil { await log.builds == 1 }
        #expect(await log.delays == 1)
        preview.reset(value)
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
        preview.rebuild(value, root: root, workspace: nil, coalescing: true)
        preview.rebuild(value, root: root, workspace: nil, coalescing: true)
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
        // A timing change: the composition plays different media times, so it needs new players.
        let second = try first.applying(.trim(item: "c", edge: .end, toFrame: 40, ripple: false)).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        let root = video.deletingLastPathComponent()
        preview.rebuild(first, root: root, workspace: nil)
        try await waitUntil { preview.isCurrent }
        let shown = preview.player
        let composition = try #require(preview.snapshot?.composition)

        preview.rebuild(second, root: root, workspace: nil)
        #expect(!preview.isCurrent && preview.currentBuild == nil)
        #expect(preview.snapshot?.composition === composition)
        #expect(preview.player === shown && shown.currentItem != nil)
        try await waitUntil { preview.isCurrent }
        #expect(preview.currentBuild?.composition === preview.snapshot?.composition)
        #expect(preview.snapshot?.composition !== composition)
        #expect(preview.player !== shown && shown.currentItem == nil)
        #expect(preview.player.currentItem?.status == .readyToPlay)
    }

    @Test("A look-only edit updates the shown players in place")
    func lookEditInPlace() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59),
        ])
        var caption = Item(id: "t", at: 0, duration: 59)
        caption["text"] = .string("Xin chào")
        let first = try Project(name: "Look").applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59)),
            .insert(track: "t1", item: caption),
        ])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        let root = video.deletingLastPathComponent()
        preview.rebuild(first, root: root, workspace: nil)
        try await waitUntil { preview.isCurrent }
        let shown = preview.player, item = preview.player.currentItem
        var edited = first
        for patch: (String, [String: JSONValue]) in [
            ("c", ["opacity": .number(0.5)]), ("c", ["color": .object(["saturation": .number(0)])]),
            ("t", ["text": .string("Tạm biệt")]),
            ("c", ["keyframes": ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1), .init(frame: 58, value: 1.3)]]).json]),
        ] {
            edited = try edited.applying(.setProperties(item: patch.0, patch: patch.1)).project
            let before = preview.inPlaceUpdates
            preview.rebuild(edited, root: root, workspace: nil)
            try await waitUntil { preview.isCurrent }
            #expect(preview.inPlaceUpdates == before + 1, "\(patch.1.keys)")
        }
        #expect(preview.player === shown && preview.player.currentItem === item)
        #expect(preview.buildCount == 5)
    }

    @Test("The shown picture follows an in-place update")
    func inPlacePicture() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59),
        ])
        let first = try Project(name: "Gray").applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59)),
        ])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        let root = video.deletingLastPathComponent()
        preview.rebuild(first, root: root, workspace: nil)
        try await waitUntil { preview.isCurrent }
        let item = try #require(preview.player.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        preview.seek(20)
        func spread() async throws -> Int {
            var buffer: CVPixelBuffer?
            for _ in 0..<200 {
                if output.hasNewPixelBuffer(forItemTime: first.fps.time(20)) {
                    buffer = output.copyPixelBuffer(forItemTime: first.fps.time(20), itemTimeForDisplay: nil)
                    if buffer != nil { break }
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(pixels)
            var widest = 0
            for y in stride(from: 0, to: CVPixelBufferGetHeight(pixels), by: 37) {
                for x in stride(from: 0, to: CVPixelBufferGetWidth(pixels), by: 37) {
                    let pixel = base + y * row + x * 4
                    let values = [Int(pixel[0]), Int(pixel[1]), Int(pixel[2])]
                    widest = max(widest, values.max()! - values.min()!)
                }
            }
            return widest
        }
        #expect(try await spread() > 20)  // the generated clip is colourful
        let gray = try first.applying(.setProperties(item: "c", patch: ["color": .object(["saturation": .number(0)])])).project
        preview.rebuild(gray, root: root, workspace: nil)
        try await waitUntil { preview.isCurrent }
        #expect(preview.inPlaceUpdates == 1)
        let after = try await spread()
        #expect(after < 6, "spread \(after)")
    }
}
