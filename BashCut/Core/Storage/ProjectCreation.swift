import BashCutProject
import Darwin
import Foundation

public struct CreatedProject: Sendable {
    public let url: URL
    public let project: Project
    public let diskData: Data
}

extension ProjectStorage {
    /// Build privately, then publish with an exclusive rename so existing folders and symlinks are never replaced.
    public func create(_ setup: ProjectSetup, in parent: URL, footage: URL? = nil) throws -> CreatedProject {
        let project = try setup.project()
        let data = try project.data()
        let manager = FileManager.default
        if let footage {
            let values = try footage.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
            guard values.isDirectory == true, values.isReadable == true else {
                throw ProjectError.invalid("Choose a readable footage folder.")
            }
        }
        let stage = parent.appendingPathComponent(".bashcut-new-" + UUID().uuidString, isDirectory: true)
        let destination = parent.appendingPathComponent(setup.folderName, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        for name in ["media", "voiceover", "subtitles", "render", ".bashcut"] {
            try manager.createDirectory(at: stage.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        ProjectCacheIgnore.ensure(in: stage.appendingPathComponent(".bashcut"))
        if let footage {
            // This is a reference only. Never change permissions or contents of the original shoot.
            try manager.createSymbolicLink(
                at: stage.appendingPathComponent("footage"), withDestinationURL: footage.standardizedFileURL)
        } else {
            try manager.createDirectory(at: stage.appendingPathComponent("footage"), withIntermediateDirectories: false)
        }
        try data.write(to: stage.appendingPathComponent("project.bashcut.json"), options: .atomic)
        let result = stage.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                renameatx_np(AT_FDCWD, source, AT_FDCWD, target, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return CreatedProject(url: destination.appendingPathComponent("project.bashcut.json"), project: project, diskData: data)
    }
}
