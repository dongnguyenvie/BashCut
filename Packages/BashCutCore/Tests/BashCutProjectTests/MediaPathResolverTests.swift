import Foundation
import Testing

@testable import BashCutProject

struct MediaPathResolverTests {
    @Test("Shared assets resolve under the configured workspace")
    func sharedAsset() throws {
        let project = URL(fileURLWithPath: "/tmp/project")
        let workspace = URL(fileURLWithPath: "/tmp/workspace")
        let resolved = try MediaPathResolver.resolve(
            "@assets/nhac/song.wav", projectRoot: project, workspaceRoot: workspace)
        #expect(resolved.path == "/tmp/workspace/assets/nhac/song.wav")
        #expect(
            try MediaPathResolver.resolve("media/local.mov", projectRoot: project).path
                == "/tmp/project/media/local.mov")
    }

    @Test("Shared paths require a workspace and cannot traverse out of assets")
    func invalidSharedAsset() {
        let project = URL(fileURLWithPath: "/tmp/project")
        #expect(throws: ProjectError.self) {
            try MediaPathResolver.resolve("@assets/music.wav", projectRoot: project)
        }
        #expect(throws: ProjectError.self) {
            try MediaPathResolver.resolve(
                "@assets/../secret", projectRoot: project,
                workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        }
    }

    @Test("Shared asset symlinks cannot escape the workspace assets directory")
    func escapingSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let assets = workspace.appendingPathComponent("assets", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: assets.appendingPathComponent("escape"), withDestinationURL: outside)
        #expect(throws: ProjectError.self) {
            try MediaPathResolver.resolve(
                "@assets/escape/secret.wav", projectRoot: root, workspaceRoot: workspace)
        }
    }
}
