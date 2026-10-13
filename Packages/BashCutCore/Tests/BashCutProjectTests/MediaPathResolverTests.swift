import Foundation
import Testing

@testable import BashCutProject

struct MediaPathResolverTests {
    @Test("Shared assets resolve under the configured workspace")
    func sharedAsset() throws {
        let project = URL(fileURLWithPath: "/tmp/project")
        let workspace = URL(fileURLWithPath: "/tmp/workspace")
        let resolved = try MediaPathResolver.resolve(
            "@assets/music/song.wav", projectRoot: project, workspaceRoot: workspace)
        #expect(resolved.path == "/tmp/workspace/assets/music/song.wav")
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

    @Test("Older ../ media paths into a linked folder are rewritten through the link")
    func relinkOlderPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Edit.bashcut", isDirectory: true)
        let shoot = root.appendingPathComponent("Downloads/shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("footage"), withDestinationURL: shoot)
        var project = Project(name: "Relink")
        project.media = [
            Media(fields: ["id": .string("a"), "path": .string("../Downloads/shoot/a.mp4")]),
            Media(fields: ["id": .string("b"), "path": .string("../Music/song.wav")]),
            Media(fields: ["id": .string("c"), "path": .string("voiceover/take.m4a")]),
        ]
        let relinked = try #require(MediaPathResolver.relinkingMedia(in: project, projectRoot: folder))
        #expect(relinked.media.map(\.path) == ["footage/a.mp4", "../Music/song.wav", "voiceover/take.m4a"])
        #expect(MediaPathResolver.relinkingMedia(in: relinked, projectRoot: folder) == nil)
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

    @Test("A converted media shows the imported file's name, not its converted copy's")
    func convertedFileName() {
        let plain = Media(fields: ["id": .string("m1"), "path": .string("footage/street.mp4")])
        #expect(plain.fileName == "street.mp4")
        let converted = Media(fields: [
            "id": .string("m2"), "path": .string("media/converted/m2.mov"), "originalPath": .string("footage/bts.mp4"),
        ])
        #expect(converted.fileName == "bts.mp4")
        let sticker = Media(fields: [
            "id": .string("m3"), "path": .string("stickers/library-9f2c.x2.mov"), "label": .string("Party popper"),
        ])
        #expect(sticker.fileName == "Party popper")
        var unlabelled = sticker
        unlabelled.fields["label"] = nil
        var project = Project(name: "Labels")
        project.media = [unlabelled]
        #expect(project.existingMedia(like: Media(fields: sticker.fields.merging(["id": .string("m4")]) { $1 }))?.id == "m3",
                "media placed before labels existed is reused")
    }
}
