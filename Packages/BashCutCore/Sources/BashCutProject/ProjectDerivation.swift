import Foundation

/// Sibling projects made from this one (P1-D9): a derived project per select or range (several shorts from one long
/// recording) keeps the media, canvas, outputs and review profile and plays only that range; a variant is a full copy
/// that records what it changes (`variant.changed`) so variants that each change one thing can be listed and diffed.
public enum ProjectDerivation {
    /// Where the new project comes from and goes: the source project's folder and file, the new folder and name.
    public struct Target: Sendable {
        public var root: URL
        public var path: String
        public var destination: URL
        public var name: String

        public init(root: URL, path: String, destination: URL, name: String) {
            self.root = root
            self.path = path
            self.destination = destination
            self.name = name
        }
    }

    /// Media whose paths resolve from the new project's folder: project-relative paths are rewritten relative to
    /// `destination` (such as `../long/footage/a.mov`); shared `@assets/` paths stay.
    static func portable(_ media: [Media], root: URL, destination: URL) -> [JSONValue] {
        media.map { asset in
            var fields = asset.fields
            if !asset.path.hasPrefix("@") {
                let target = root.appendingPathComponent(asset.path).standardizedFileURL
                fields["path"] = .string(relativePath(to: target, from: destination.standardizedFileURL))
            }
            return .object(fields)
        }
    }

    static func relativePath(to target: URL, from folder: URL) -> String {
        let to = target.pathComponents, from = folder.pathComponents
        var shared = 0
        while shared < min(to.count, from.count), to[shared] == from[shared] { shared += 1 }
        return (Array(repeating: "..", count: from.count - shared) + to[shared...]).joined(separator: "/")
    }

    static func origin(_ project: Project, path: String) -> JSONValue {
        .object(["path": .string(path), "id": project["id"] ?? .null, "rev": .integer(project.revision)])
    }

    /// A full copy under a new ID and name, with `variant {of, changed}`.
    public static func variant(of project: Project, target: Target, changed: String) -> Project {
        var fields = project.fields
        fields["id"] = .string(UUID().uuidString)
        fields["name"] = .string(target.name)
        fields["rev"] = .integer(0)
        fields["media"] = .array(portable(project.media, root: target.root, destination: target.destination))
        fields["variant"] = .object(["of": origin(project, path: target.path), "changed": .string(changed)])
        fields["derivedFrom"] = nil
        return Project(fields: fields)
    }

    /// The same canvas, outputs, review profile, brief and media with empty layers and the select's range on Main.
    public static func derived(from project: Project, target: Target, select: ProjectSelect) throws -> Project {
        guard let media = project.media.first(where: { $0.id == select.media }) else {
            throw ProjectError.invalid("Select \(select.id): media \(select.media) is not in the project")
        }
        var fields = project.fields
        fields["id"] = .string(UUID().uuidString)
        fields["name"] = .string(target.name)
        fields["rev"] = .integer(0)
        fields["media"] = .array(
            portable(project.media.filter { $0.id == media.id }, root: target.root, destination: target.destination))
        fields["tracks"] = .array(project.tracks.map { track in
            var copy = track
            copy.items = []
            return .object(copy.fields)
        })
        for key in ["markers", "transitions"] { fields[key] = .array([]) }
        for key in ["selects", "plan", "beatGrid", "variant"] { fields[key] = nil }
        fields["derivedFrom"] = .object([
            "project": origin(project, path: target.path), "select": .string(select.id),
            "from": .number(select.from), "to": .number(select.to),
        ])
        var derived = Project(fields: fields)
        let main = try derived.requireTrack(role: TrackRole.main, kind: "video").id
        var planner = LayerPlanner(derived)
        let portableMedia = derived.media[0]
        try planner.placeMedia(
            portableMedia, on: main, at: 0, duration: Int(((select.to - select.from) * project.fps.value).rounded()),
            sourceIn: Int((select.from * media.fps.value).rounded(.down)))
        derived = try derived.applying(.group(label: "Derive", author: .agent, ops: planner.operations)).project
        derived.revision = 0
        return derived
    }

    /// What differs between two projects: top-level fields, and per track the items added, removed or changed.
    public static func diff(_ left: Project, _ right: Project) -> JSONValue {
        let skip: Set<String> = ["id", "name", "rev", "tracks", "variant", "derivedFrom"]
        let keys = Set(left.fields.keys).union(right.fields.keys).subtracting(skip).sorted()
        let fields = keys.filter { left.fields[$0] != right.fields[$0] }
        let items = { (project: Project) in
            Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let before = items(left), after = items(right)
        let changed = before.keys.filter { after[$0] != nil && after[$0] != before[$0] }.sorted()
        return .object([
            "fields": .array(fields.map(JSONValue.string)),
            "items": .object([
                "added": .array(after.keys.filter { before[$0] == nil }.sorted().map(JSONValue.string)),
                "removed": .array(before.keys.filter { after[$0] == nil }.sorted().map(JSONValue.string)),
                "changed": .array(changed.map(JSONValue.string)),
            ]),
            "duration": .object(["left": .integer(left.duration), "right": .integer(right.duration)]),
            "changedAs": .object([
                "left": left["variant"]?.object["changed"] ?? .null, "right": right["variant"]?.object["changed"] ?? .null,
            ]),
        ])
    }
}
