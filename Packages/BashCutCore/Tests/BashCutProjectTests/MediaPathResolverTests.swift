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

    @Test("Files under the linked footage folder are stored through the link")
    func linkedFootagePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("Edit.bashcut", isDirectory: true)
        let shoot = root.appendingPathComponent("Downloads/shoot", isDirectory: true)
        try FileManager.default.createDirectory(
            at: shoot.appendingPathComponent("day1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("footage"), withDestinationURL: shoot)

        let picked = shoot.appendingPathComponent("day1/DJI_0001.MP4")
        #expect(MediaPathResolver.projectPath(for: picked, projectRoot: project) == "footage/day1/DJI_0001.MP4")
        let viaLink = project.appendingPathComponent("footage/clip.mov")
        #expect(MediaPathResolver.projectPath(for: viaLink, projectRoot: project) == "footage/clip.mov")
        let local = project.appendingPathComponent("voiceover/take.m4a")
        #expect(MediaPathResolver.projectPath(for: local, projectRoot: project) == "voiceover/take.m4a")
        let resolvedLocal = local.resolvingSymlinksInPath()
        #expect(MediaPathResolver.projectPath(for: resolvedLocal, projectRoot: project) == "voiceover/take.m4a")
        let outside = root.appendingPathComponent("Music/song.wav")
        #expect(MediaPathResolver.projectPath(for: outside, projectRoot: project) == "../Music/song.wav")
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
