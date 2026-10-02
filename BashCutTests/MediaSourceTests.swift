import BashCutProject
import Foundation
import Testing

@testable import BashCutEngine

/// Engine media tests on a copy of the fixture clip, so files can be replaced and proxies added.
struct MediaSourceTests {
    private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/media/test.mp4")

    private func projectFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("clip.mp4"))
        return root
    }

    private func media(id: String = "clip") -> Media {
        Media(fields: [
            "id": .string(id), "path": .string("clip.mp4"), "fps": FrameRate().json, "frames": .integer(59),
        ])
    }

    private func project() throws -> Project {
        try Project(name: "Cache").applying(
            .group(
                label: "Fixture", author: .user,
                ops: [.addMedia(media()), .insert(track: "v1", item: Item(media: "clip", at: 0, duration: 30))])
        ).project
    }

    @Test("Previews read a proxy when one exists; exports always read the original")
    func proxySelection() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ProxyMediaSource()
        let original = root.appendingPathComponent("clip.mp4").standardizedFileURL
        #expect(try source.url(for: media(), root: root, workspace: nil, purpose: .preview).standardizedFileURL == original)

        let proxies = root.appendingPathComponent(ProxyMediaSource.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: proxies.appendingPathComponent("clip.mov"))
        #expect(try source.url(for: media(), root: root, workspace: nil, purpose: .preview).lastPathComponent == "clip.mov")
        #expect(try source.url(for: media(), root: root, workspace: nil, purpose: .export).standardizedFileURL == original)
        #expect(ProxyMediaSource.proxyURL(for: media(id: "../clip"), root: root) == nil)
        #expect(ProxyMediaSource.proxyURL(for: media(id: ".hidden"), root: root) == nil)
    }

    @Test("Builds reuse opened assets until the file changes on disk")
    func assetCache() async throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let builder = CompositionBuilder(source: OriginalMediaSource())
        let value = try project()
        _ = try await builder.build(value, root: root, purpose: .preview)
        _ = try await builder.build(value, root: root, purpose: .preview)
        #expect(await builder.assetLoads == 1)
        #expect(await builder.cachedAssetCount == 1)

        let clip = root.appendingPathComponent("clip.mp4")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: clip.path)
        _ = try await builder.build(value, root: root, purpose: .preview)
        #expect(await builder.assetLoads == 2)
        #expect(await builder.cachedAssetCount == 1)
    }

    @Test("The cache keeps at most its limit, dropping the least recently used asset")
    func cacheLimit() async throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let proxies = root.appendingPathComponent(ProxyMediaSource.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: proxies.appendingPathComponent("clip.mp4"))
        let builder = CompositionBuilder(source: ProxyMediaSource(), cacheLimit: 1)
        let value = try project()
        _ = try await builder.build(value, root: root, purpose: .preview)
        _ = try await builder.build(value, root: root, purpose: .export)
        _ = try await builder.build(value, root: root, purpose: .preview)
        #expect(await builder.cachedAssetCount == 1)
        #expect(await builder.assetLoads == 3)
    }
}
