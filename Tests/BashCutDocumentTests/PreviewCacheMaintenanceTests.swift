import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@MainActor
struct PreviewCacheMaintenanceTests {
    private enum Failure: Error { case expected }

    @Test("Cache maintenance releases both players, defers edits, and restores the latest preview even on failure", arguments: [false, true])
    func maintenance(comparison: Bool) async throws {
        let video = try await TestFixtures.requireVideo()
        let media = Media(fields: ["id": .string("m"), "path": .string(video.lastPathComponent),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        let first = try Project(name: "Maintenance").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 59))
        ])).project
        let latest = try first.applying(.trim(item: "c", edge: .end, toFrame: 30, ripple: false)).project
        let root = video.deletingLastPathComponent()
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        preview.rebuild(first, root: root, workspace: nil)
        try await ready(preview)
        if comparison { preview.setColorComparison(true); try await ready(preview) }
        preview.seek(20)
        let count = preview.buildCount
        await #expect(throws: Failure.self) {
            try await preview.maintainCache {
                #expect(preview.isMaintainingCache)
                #expect(preview.player.currentItem == nil && preview.comparisonPlayer.currentItem == nil)
                #expect(preview.currentBuild == nil && preview.snapshot == nil)
                do {
                    try await preview.maintainCache {}
                    Issue.record("Nested maintenance should fail")
                } catch is ProjectError {}
                preview.rebuild(latest, root: root, workspace: nil)
                await Task.yield()
                #expect(preview.buildCount == count)
                throw Failure.expected
            }
        }
        #expect(!preview.isMaintainingCache)
        try await ready(preview)
        #expect(preview.buildCount == count + 1)
        #expect(preview.playhead == 20)
        #expect(preview.showColorComparison == comparison)
        #expect(preview.currentBuild?.composition.duration == latest.fps.time(30))
        preview.reset(latest)
    }

    @Test("Cache removal waits for cancellation of the previous build task")
    func drainsBuild() async throws {
        let state = MaintenanceDelay()
        let preview = PreviewController(engine: AVFoundationRenderEngine(), coalescingDelay: {
            await state.begin()
            do { try await Task.sleep(for: .seconds(30)) } catch {
                await state.end()
                throw error
            }
        })
        var caption = Item(id: "t", at: 0, duration: 30)
        caption["text"] = .string("Test")
        let project = try Project(name: "Drain").applying(.insert(track: "t1", item: caption)).project
        let root = try TestFixtures.temporaryDirectory("preview-drain")
        defer { try? FileManager.default.removeItem(at: root) }
        preview.rebuild(project, root: root, workspace: nil, coalescing: true)
        for _ in 0..<500 {
            if await state.began { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await state.began)
        try await preview.maintainCache { #expect(await state.ended) }
        preview.reset(project)
    }

    private func ready(_ preview: PreviewController) async throws {
        for _ in 0..<500 where !preview.isCurrent { try await Task.sleep(for: .milliseconds(10)) }
        #expect(preview.isCurrent)
    }
}

private actor MaintenanceDelay {
    private(set) var began = false
    private(set) var ended = false
    func begin() { began = true }
    func end() { ended = true }
}
