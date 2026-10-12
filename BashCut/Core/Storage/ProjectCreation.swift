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
        let destination = parent.appendingPathComponent(setup.folderName, isDirectory: true)
        if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw ProjectError.invalid("\(destination.path) is a link; choose another project name")
        }
        var isFolder: ObjCBool = false
        if manager.fileExists(atPath: destination.path, isDirectory: &isFolder) {
            guard isFolder.boolValue else { throw ProjectError.invalid("\(destination.path) is a file; choose another project name") }
            return try adopt(destination, project: project, data: data, footage: footage)
        }
        let stage = parent.appendingPathComponent(".bashcut-new-" + UUID().uuidString, isDirectory: true)
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

    /// Makes a project in a folder that already exists without one (#507-38), such as a folder the footage was
    /// copied into: the missing project folders are added, and nothing in the folder is moved or replaced.
    private func adopt(_ folder: URL, project: Project, data: Data, footage: URL?) throws -> CreatedProject {
        let manager = FileManager.default
        let file = folder.appendingPathComponent("project.bashcut.json")
        guard !manager.fileExists(atPath: file.path) else {
            throw ProjectError.invalid("\(folder.path) already holds a project; open it with project open")
        }
        for name in ["media", "voiceover", "subtitles", "render", ".bashcut"] {
            let url = folder.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            if manager.fileExists(atPath: url.path, isDirectory: &isFolder) {
                guard isFolder.boolValue else { throw ProjectError.invalid("\(url.path) is a file, not a folder") }
            } else {
                try manager.createDirectory(at: url, withIntermediateDirectories: false)
            }
        }
        ProjectCacheIgnore.ensure(in: folder.appendingPathComponent(".bashcut"))
        // A footage folder or link already there stays; footage inside the project folder is not linked to itself.
        let link = folder.appendingPathComponent("footage")
        let present = manager.fileExists(atPath: link.path) || (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil
        if !present {
            let root = folder.standardizedFileURL.path
            if let footage = footage?.standardizedFileURL, footage.path != root, !footage.path.hasPrefix(root + "/") {
                try manager.createSymbolicLink(at: link, withDestinationURL: footage)
            } else {
                try manager.createDirectory(at: link, withIntermediateDirectories: false)
            }
        }
        try data.write(to: file, options: .withoutOverwriting)
        return CreatedProject(url: file, project: project, diskData: data)
    }
}
