import BashCutProject
import Foundation
import Testing

@testable import BashCutEngine

struct LUTCacheTests {
    private func cube(_ value: String = "0 0 0") -> Data {
        Data(("LUT_3D_SIZE 2\n" + String(repeating: value + "\n", count: 8)).utf8)
    }

    @Test("LUT cache reuses parses, invalidates file changes, and checks catalog dimensions on hits")
    func invalidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.cube")
        try cube().write(to: url)
        var cache = LUTCache()
        let first = try cache.load(url, dimension: 2)
        #expect(try cache.load(url, dimension: 2).cubeData == first.cubeData)
        #expect(cache.loads == 1)
        #expect(throws: ProjectError.self) { try cache.load(url, dimension: 3) }
        try cube("0.5 0 0").write(to: url, options: .atomic)
        #expect(try cache.load(url, dimension: 2).cubeData != first.cubeData)
        #expect(cache.loads == 2)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try cache.load(url, dimension: 2) }
    }

    @Test("LUT cache distinguishes paths and evicts least recently used cubes within its byte budget")
    func eviction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = (0..<3).map { root.appendingPathComponent("\($0).cube") }
        for url in urls { try cube().write(to: url) }
        var cache = LUTCache(maximumBytes: 256) // Two 2³ RGBA float cubes.
        _ = try cache.load(urls[0], dimension: 2)
        _ = try cache.load(urls[1], dimension: 2)
        _ = try cache.load(urls[0], dimension: 2) // Keep 0; 1 is now oldest.
        _ = try cache.load(urls[2], dimension: 2)
        #expect(cache.loads == 3)
        _ = try cache.load(urls[0], dimension: 2)
        #expect(cache.loads == 3)
        _ = try cache.load(urls[1], dimension: 2)
        #expect(cache.loads == 4)
        #expect(cache.bytes == 256)
    }
}
