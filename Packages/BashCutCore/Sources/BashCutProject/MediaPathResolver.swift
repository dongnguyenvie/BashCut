import Foundation

public enum MediaPathResolver {
    public static func resolve(
        _ path: String, projectRoot: URL, workspaceRoot: URL? = nil
    ) throws -> URL {
        guard path.hasPrefix("@") else {
            return projectRoot.appendingPathComponent(path).standardizedFileURL
        }
        guard path.hasPrefix("@assets/"), let workspaceRoot else {
            throw ProjectError.invalid("Shared media requires a configured workspace")
        }
        let relative = String(path.dropFirst("@assets/".count))
        guard validSharedPath(relative) else {
            throw ProjectError.invalid("Invalid shared media path")
        }
        let root = workspaceRoot.standardizedFileURL
        let assets = root.appendingPathComponent("assets").resolvingSymlinksInPath().standardizedFileURL
        let prefix = assets.path + "/"
        var resolved = assets
        for component in relative.split(separator: "/") {
            resolved = resolved.appendingPathComponent(String(component)).resolvingSymlinksInPath()
                .standardizedFileURL
            guard resolved.path.hasPrefix(prefix) else {
                throw ProjectError.invalid("Shared media escapes the workspace assets folder")
            }
        }
        return resolved
    }

    /// The path a project at `projectRoot` stores for `url`. A file reached through a folder
    /// symlink at the top of the project (the linked `footage` folder) is stored through that
    /// link, so the project keeps working when it moves together with its link.
    public static func projectPath(for url: URL, projectRoot: URL) -> String {
        let file = url.standardizedFileURL
        let root = projectRoot.standardizedFileURL
        if let inside = descendant(file, of: root) { return inside }
        let resolvedFile = file.resolvingSymlinksInPath()
        for link in linkedFolders(in: root) {
            if let inside = descendant(resolvedFile, of: link.destination) { return link.name + "/" + inside }
        }
        if let inside = descendant(resolvedFile, of: root.resolvingSymlinksInPath()) { return inside }
        let source = file.pathComponents
        let base = root.pathComponents
        let common = zip(source, base).prefix { $0 == $1 }.count
        return (Array(repeating: "..", count: base.count - common) + source.dropFirst(common))
            .joined(separator: "/")
    }

    /// `project` with `../` media paths that point into a linked project folder rewritten to go
    /// through the link (see `projectPath`), or nil when nothing changes.
    public static func relinkingMedia(in project: Project, projectRoot: URL) -> Project? {
        var changed = false
        let media = project.media.map { entry -> Media in
            guard entry.path.hasPrefix("../") else { return entry }
            let url = projectRoot.appendingPathComponent(entry.path).standardizedFileURL
            let path = projectPath(for: url, projectRoot: projectRoot)
            guard path != entry.path, !path.hasPrefix("../") else { return entry }
            var relinked = entry
            relinked.fields["path"] = .string(path)
            changed = true
            return relinked
        }
        guard changed else { return nil }
        var result = project
        result.media = media
        return result
    }

    private static func descendant(_ url: URL, of folder: URL) -> String? {
        let source = url.pathComponents
        let base = folder.pathComponents
        guard source.count > base.count, Array(source.prefix(base.count)) == base else { return nil }
        return source.dropFirst(base.count).joined(separator: "/")
    }

    /// Top-level folder symlinks of `root`, longest destination first.
    private static func linkedFolders(in root: URL) -> [(name: String, destination: URL)] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)) ?? []
        return entries.compactMap { entry -> (name: String, destination: URL)? in
            guard (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
                return nil
            }
            let destination = entry.resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }
            return (entry.lastPathComponent, destination)
        }
        .sorted { $0.destination.pathComponents.count > $1.destination.pathComponents.count }
    }

    public static func validSharedPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains {
                $0.isEmpty || $0 == "." || $0 == ".."
            }
    }
}
