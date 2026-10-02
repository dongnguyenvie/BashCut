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

    public static func validSharedPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains {
                $0.isEmpty || $0 == "." || $0 == ".."
            }
    }
}
