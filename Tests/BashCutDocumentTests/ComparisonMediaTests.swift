import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@MainActor
struct ComparisonMediaTests {
    @Test("Color edits reuse comparison; fresh proxies and same-metadata file replacements invalidate it")
    func mediaFreshness() async throws {
        let video = try await TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("comparison")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: video, to: root.appendingPathComponent("source.mp4"))
        let media = Media(fields: ["id": .string("m"), "path": .string("source.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        var project = try Project(name: "Compare").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 59))
        ])).project
        let preview = PreviewController(engine: AVFoundationRenderEngine())
        defer { preview.reset(project) }
        preview.setColorComparison(true)
        preview.rebuild(project, root: root, workspace: nil)
        try await ready(preview)
        let comparisonPlayer = preview.comparisonPlayer
        for amount in [0.2, 0.4, 0.6] {
            project = try project.applying(.setProperties(item: "c", patch: ["color": .object(["saturation": .number(amount)])])).project
            preview.rebuild(project, root: root, workspace: nil)
            try await ready(preview)
        }
        #expect(preview.comparisonBuildCount == 1 && preview.comparisonReuseCount == 3)
        #expect(preview.comparisonPlayer === comparisonPlayer)
        let proxies = root.appendingPathComponent(ProxyMediaSource.folder)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        let proxy = proxies.appendingPathComponent("m.mp4")
        try FileManager.default.copyItem(at: video, to: proxy)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: proxy.path)
        preview.rebuild(project, root: root, workspace: nil)
        try await ready(preview)
        #expect(preview.comparisonBuildCount == 2)
        let old = try FileManager.default.attributesOfItem(atPath: proxy.path)
        let replacement = proxies.appendingPathComponent("replacement.mp4")
        try FileManager.default.copyItem(at: video, to: replacement)
        try FileManager.default.setAttributes([.modificationDate: try #require(old[.modificationDate])], ofItemAtPath: replacement.path)
        try FileManager.default.removeItem(at: proxy)
        try FileManager.default.moveItem(at: replacement, to: proxy)
        let changed = try FileManager.default.attributesOfItem(atPath: proxy.path)
        #expect((old[.systemFileNumber] as? UInt64) != (changed[.systemFileNumber] as? UInt64))
        #expect((old[.modificationDate] as? Date) == (changed[.modificationDate] as? Date))
        preview.rebuild(project, root: root, workspace: nil)
        try await ready(preview)
        #expect(preview.comparisonBuildCount == 3)
        project = try project.applying(.setProperties(item: "c", patch: ["opacity": .number(0.5)])).project
        preview.rebuild(project, root: root, workspace: nil)
        try await ready(preview)
        #expect(preview.comparisonBuildCount == 4)
    }

    private func ready(_ preview: PreviewController) async throws {
        for _ in 0..<500 where !preview.isCurrent { try await Task.sleep(for: .milliseconds(10)) }
        #expect(preview.isCurrent)
    }
}
