import BashCutAutomation
import BashCutProject
import Foundation

/// Derived projects and variants (P1-D9): sibling project folders written next to this one; nothing in the open
/// project changes, and nothing opens.
extension ProjectDocument {
    func registerVariantCommands() {
        handleAuthored("project.derive") { document, arguments, _ in
            let (root, path) = try document.savedProjectRoot()
            let ids = arguments.optionalString("ids").map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
            let selects = document.project.selects.filter { ids?.contains($0.id) ?? ($0.status == "kept") }
            guard !selects.isEmpty else { throw RPCFailure(-32602, "No selects to derive from (mark some kept, or give ids)") }
            let parent = try document.siblingParent(arguments, root: root)
            var created: [JSONValue] = []
            for select in selects {
                let name = "\(document.project.name) – \(select.id)"
                let folder = Self.folder(root.lastPathComponent + "-" + select.id, in: parent)
                let project = try ProjectDerivation.derived(
                    from: document.project, target: .init(root: root, path: path, destination: folder, name: name), select: select)
                let url = try Self.writeSibling(project, to: folder)
                created.append(.object(["select": .string(select.id), "path": .string(url.path)]))
            }
            return .object(["projects": .array(created)])
        }
        handleAuthored("variants.create") { document, arguments, _ in
            let (root, path) = try document.savedProjectRoot()
            let changed = try arguments.string("changed")
            let suffix = try arguments.string("name")
            let folder = Self.folder(root.lastPathComponent + "-" + suffix, in: try document.siblingParent(arguments, root: root))
            let project = ProjectDerivation.variant(
                of: document.project,
                target: .init(root: root, path: path, destination: folder, name: "\(document.project.name) – \(suffix)"),
                changed: changed)
            let url = try Self.writeSibling(project, to: folder)
            return .object(["path": .string(url.path), "changed": .string(changed)])
        }
        handle("variants.list") { document, arguments, _ in
            let (root, _) = try document.savedProjectRoot()
            let id = document.project["id"]?.string ?? ""
            let parent = try document.siblingParent(arguments, root: root)
            let folders = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            let rows: [JSONValue] = folders.sorted { $0.path < $1.path }.compactMap { folder in
                let file = folder.appendingPathComponent("project.bashcut.json")
                guard let data = try? Data(contentsOf: file), case .object(let fields)? = try? JSONValue(parsing: data) else { return nil }
                let variantOf = fields["variant"]?.object["of"]?.object["id"]?.string
                let derivedOf = fields["derivedFrom"]?.object["project"]?.object["id"]?.string
                guard variantOf == id || derivedOf == id else { return nil }
                return .object([
                    "path": .string(file.path), "name": fields["name"] ?? .null,
                    "kind": .string(variantOf == id ? "variant" : "derived"),
                    "changed": fields["variant"]?.object["changed"] ?? .null,
                    "select": fields["derivedFrom"]?.object["select"] ?? .null, "rev": fields["rev"] ?? .null,
                ])
            }
            return .object(["variants": .array(rows)])
        }
        handle("variants.diff") { document, arguments, _ in
            let read = { (path: String) throws -> Project in
                var url = URL(fileURLWithPath: path)
                if url.pathExtension != "json" { url.appendPathComponent("project.bashcut.json") }
                guard let data = try? Data(contentsOf: url), case .object(let fields)? = try? JSONValue(parsing: data) else {
                    throw RPCFailure(-32602, "Cannot read a project at \(path)")
                }
                return Project(fields: fields)
            }
            let left = try arguments.optionalString("base").map(read) ?? document.project
            return ProjectDerivation.diff(left, try read(try arguments.string("other")))
        }
    }

    /// The saved project's folder and file path.
    func savedProjectRoot() throws -> (root: URL, path: String) {
        guard let fileURL else { throw RPCFailure(-32602, "Save the project first") }
        return (fileURL.deletingLastPathComponent(), fileURL.path)
    }

    /// Where sibling projects go: `directory`, else the folder that holds this project's folder.
    func siblingParent(_ arguments: CommandArguments, root: URL) throws -> URL {
        let parent = arguments.optionalString("directory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? root.deletingLastPathComponent()
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw RPCFailure(-32602, "\(parent.path) is not a folder")
        }
        return parent
    }

    static func folder(_ name: String, in parent: URL) -> URL {
        parent.appendingPathComponent(
            name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"), isDirectory: true)
    }

    /// Writes `project` into a new folder; an existing folder is never touched.
    static func writeSibling(_ project: Project, to destination: URL) throws -> URL {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RPCFailure(-32602, "\(destination.path) already exists; choose another name")
        }
        try project.validate()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let file = destination.appendingPathComponent("project.bashcut.json")
        try project.data().write(to: file, options: .atomic)
        return file
    }
}
