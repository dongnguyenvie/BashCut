import AVFoundation
@testable import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@MainActor
struct PlayerItemReadinessTests {
    @Test("Unknown item readiness times out without polling")
    func timeout() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        await #expect(throws: PlayerItemReadiness.Timeout.self) {
            try await PlayerItemReadiness.wait(item, message: "Timeout", timeout: .milliseconds(20))
        }
    }

    @Test("Cancellation tears down unknown-item readiness promptly", arguments: [false, true])
    func cancellation(immediate: Bool) async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let task = Task { try await PlayerItemReadiness.wait(item, message: "Timeout", timeout: .seconds(30)) }
        if !immediate { try await Task.sleep(for: .milliseconds(20)) }
        task.cancel()
        try await task.valueOrCancellation()
    }

    @Test("Readiness timeout keeps the old picture and reports the new preview as stale")
    func retainedPicture() async throws {
        let video = try TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("clip"), "path": .string(video.lastPathComponent), "fps": FrameRate().json, "frames": .integer(59)
        ])
        let first = try Project(name: "Timeout").applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "clip", at: 0, duration: 59))
        ])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine(source: OriginalMediaSource()))
        let root = video.deletingLastPathComponent()
        preview.rebuild(first, root: root, workspace: nil)
        for _ in 0..<500 where !preview.isCurrent { try await Task.sleep(for: .milliseconds(10)) }
        #expect(preview.isCurrent)
        let player = preview.player
        var message = ""
        preview.onMessage = { message = $0 }
        preview.awaitReadiness = { _, _ in throw PlayerItemReadiness.Timeout(message: "Slow preview") }
        let edited = try first.applying(.trim(item: "c", edge: .end, toFrame: 30, ripple: false)).project
        preview.rebuild(edited, root: root, workspace: nil)
        for _ in 0..<500 where message.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(message == "Slow preview")
        #expect(preview.player === player)
        #expect(preview.snapshot != nil)
        #expect(!preview.isCurrent)
        preview.reset(edited)
    }
}

private extension Task where Success == Void, Failure == any Error {
    func valueOrCancellation() async throws {
        do {
            try await value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
    }
}
