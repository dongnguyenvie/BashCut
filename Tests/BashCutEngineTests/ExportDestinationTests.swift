import Foundation
import BashCutTestSupport
import Testing
@testable import BashCutEngine

struct ExportDestinationTests {
    @Test("Staging cleanup removes writer sidecars while preserving the published movie")
    func sidecars() throws {
        let root = try TestFixtures.temporaryDirectory("export-sidecars")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("movie.mp4")
        let destination = try ExportDestination(final)
        try Data("movie".utf8).write(to: destination.partial)
        let sidecar = destination.partial.deletingLastPathComponent().appendingPathComponent("writer.sb-temporary")
        try Data("sidecar".utf8).write(to: sidecar)
        try destination.publish()
        destination.discard()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["movie.mp4"])
        #expect(try Data(contentsOf: final) == Data("movie".utf8))
    }

    @Test("Partial names stay bounded even when the final UTF-8 filename is near the filesystem limit")
    func longName() throws {
        let root = try TestFixtures.temporaryDirectory("long-export-name")
        defer { try? FileManager.default.removeItem(at: root) }
        let name = String(repeating: "ộ", count: 75) + ".mp4"
        let final = root.appendingPathComponent(name)
        let destination = try ExportDestination(final)
        #expect(destination.partial.lastPathComponent.utf8.count < 80)
        try Data("completed".utf8).write(to: destination.partial)
        try destination.publish()
        #expect(try Data(contentsOf: final) == Data("completed".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.partial.path))
    }
}
