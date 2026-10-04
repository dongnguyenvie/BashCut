import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// Engine media tests on a copy of the fixture clip, so files can be replaced and proxies added.
struct MediaSourceTests {
    private let fixture = TestFixtures.videoURL

    private func projectFolder() async throws -> URL {
        _ = try await TestFixtures.requireVideo()
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
    func proxySelection() async throws {
        let root = try await projectFolder()
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
        let root = try await projectFolder()
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

    @Test("A heavily cut source is resolved once per build, with fresh proxy selection on the next build")
    func repeatedSource() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingMediaSource()
        let builder = CompositionBuilder(source: source)
        let clips = (0..<240).map { EditOperation.insert(track: "v1", item: Item(id: "clip-\($0)", media: "clip", at: $0, duration: 1)) }
        let value = try Project(name: "Many cuts").applying(.group(label: "Fixture", author: .user, ops: [.addMedia(media())] + clips)).project
        _ = try await builder.build(value, root: root, purpose: .preview)
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            _ = try await builder.build(value, root: root, purpose: .preview)
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        print("REPEATED_MEDIA_BUILD median_ms=\(times.sorted()[2]) resolutions=\(source.count)")
        #expect(source.count == 6, "Each build resolves the source once regardless of clip count")
        let proxies = root.appendingPathComponent(ProxyMediaSource.folder)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: proxies.appendingPathComponent("clip.mov"))
        _ = try await builder.build(value, root: root, purpose: .preview)
        #expect(await builder.assetLoads == 2, "A proxy added between builds must be selected")
        #expect(source.count == 7)
    }

    @Test("Large projects retain every active asset across warm builds")
    func largeAssetCache() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var operations: [EditOperation] = []
        for index in 0..<80 {
            let name = "media-\(index).mp4"
            try FileManager.default.linkItem(at: root.appendingPathComponent("clip.mp4"), to: root.appendingPathComponent(name))
            var entry = media(id: "m\(index)")
            entry["path"] = .string(name)
            operations += [.addMedia(entry), .insert(track: "v1", item: Item(id: "c\(index)", media: entry.id, at: index, duration: 1))]
        }
        let value = try Project(name: "80 assets").applying(.group(label: "Fixture", author: .user, ops: operations)).project
        let builder = CompositionBuilder(source: OriginalMediaSource())
        _ = try await builder.build(value, root: root, purpose: .preview)
        var times: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            _ = try await builder.build(value, root: root, purpose: .preview)
            let duration = start.duration(to: .now).components
            times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
        print("LARGE_ASSET_CACHE median_ms=\(times.sorted()[1]) opens=\(await builder.assetLoads)")
        #expect(await builder.assetLoads == 80)
        #expect(await builder.cachedAssetCount == 80)
    }

    @Test("The purpose cache evicts the least recently used asset and shrinks for smaller projects")
    func leastRecentlyUsed() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = (0..<3).map { root.appendingPathComponent("copy-\($0).mp4") }
        for url in urls { try FileManager.default.linkItem(at: root.appendingPathComponent("clip.mp4"), to: url) }
        let cache = AssetCache(minimumCapacity: 1)
        await cache.resize(for: 2)
        _ = try await cache.load(urls[0])
        _ = try await cache.load(urls[1])
        _ = try await cache.load(urls[0])
        _ = try await cache.load(urls[2])
        _ = try await cache.load(urls[0])
        #expect(await cache.loads == 3)
        #expect(await cache.count == 2)
        _ = try await cache.load(urls[1])
        #expect(await cache.loads == 4)
        await cache.resize(for: 1)
        #expect(await cache.count == 1)
        _ = try await cache.load(urls[1])
        #expect(await cache.loads == 4)
    }

    @Test("Export assets cannot evict preview proxies")
    func cacheLimit() async throws {
        let root = try await projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let proxies = root.appendingPathComponent(ProxyMediaSource.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: proxies.appendingPathComponent("clip.mp4"))
        let builder = CompositionBuilder(source: ProxyMediaSource(), cacheLimit: 1)
        let value = try project()
        _ = try await builder.build(value, root: root, purpose: .preview)
        _ = try await builder.build(value, root: root, purpose: .export)
        _ = try await builder.build(value, root: root, purpose: .preview)
        #expect(await builder.cachedAssetCount == 2)
        #expect(await builder.assetLoads == 2)
    }
}

private final class CountingMediaSource: MediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    func url(for media: Media, root: URL, workspace: URL?, purpose: RenderPurpose) throws -> URL {
        lock.withLock { calls += 1 }
        return try ProxyMediaSource().url(for: media, root: root, workspace: workspace, purpose: purpose)
    }
}
