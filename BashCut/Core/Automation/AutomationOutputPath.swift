import Foundation

/// Restricts automated transcript writes to the project, including symlinked parent directories.
public enum AutomationOutputPath {
    public static func resolve(_ path: String, projectRoot: URL?) throws -> URL {
        guard let projectRoot, !path.isEmpty else {
            throw RPCFailure(-32602, "Open a saved project and give /export a path inside it")
        }
        let root = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        let expanded = (path as NSString).expandingTildeInPath
        let destination = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded)
                           : root.appendingPathComponent(expanded)).standardizedFileURL
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue,
            (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil else {
            throw RPCFailure(-32602, "Transcript export needs an existing folder and a non-symlink file")
        }
        let resolved = parent.appendingPathComponent(destination.lastPathComponent)
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw RPCFailure(-32602, "Automated transcript exports must stay inside the open project folder")
        }
        return resolved
    }
}
