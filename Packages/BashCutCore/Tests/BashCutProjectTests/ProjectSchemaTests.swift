import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Project JSON Schema")
struct ProjectSchemaTests {
    private static let published = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/reference/project.schema.json")

    @Test("docs/reference/project.schema.json is generated from ProjectSchema (scripts/update-schema.sh)")
    func publishedFileIsCurrent() throws {
        let generated = try ProjectSchema.data()
        if ProcessInfo.processInfo.environment["BASHCUT_UPDATE_SCHEMA"] == "1" {
            try generated.write(to: Self.published, options: .atomic)
        }
        let published = try Data(contentsOf: Self.published)
        #expect(published == generated, "Run scripts/update-schema.sh after changing ProjectSchema")
    }

    @Test("Every $ref resolves")
    func references() throws {
        let document = ProjectSchema.document
        var refs: [String] = []
        func collect(_ value: JSONValue) {
            switch value {
            case .object(let fields):
                if let ref = fields["$ref"]?.string { refs.append(ref) }
                fields.values.forEach(collect)
            case .array(let values): values.forEach(collect)
            default: break
            }
        }
        collect(document)
        #expect(!refs.isEmpty)
        for ref in refs { #expect(SchemaChecker(document).resolve(ref) != nil, "\(ref)") }
    }

    @Test("Valid projects conform to the schema")
    func validProjects() throws {
        let checker = SchemaChecker(ProjectSchema.document)
        let empty = try checker.errors(json(Project(name: "Empty")))
        #expect(empty.isEmpty, "\(empty)")
        let rich = try richProject()
        try rich.validate()
        let errors = try checker.errors(json(rich))
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test("Projects that fail validation also fail the schema")
    func invalidProjects() throws {
        let checker = SchemaChecker(ProjectSchema.document)
        let base = try richProject()
        let cases: [(String, (inout Project) -> Void)] = [
            ("unknown layer kind", { $0.tracks[1].fields["kind"] = .string("hologram") }),
            ("media on an adjustment", { project in
                Self.editItem(&project, "grade") { $0["media"] = .string("m") }
            }),
            ("text item without text", { project in Self.editItem(&project, "cap") { $0["text"] = nil } }),
            ("color out of range", { project in
                Self.editItem(&project, "grade") { $0["color"] = .object(["saturation": .integer(9)]) }
            }),
            ("unknown text preset", { project in
                Self.editItem(&project, "cap") { $0["textPreset"] = .string("comic-sans") }
            }),
            ("bad look ID", { $0["looks"] = .array([.object(["id": .string("Bad ID"), "title": .string("x"), "color": .object([:])])]) }),
            ("kit with unknown caption preset", { project in
                project["styleKits"] = .array([.object([
                    "id": .string("k"), "title": .string("K"), "look": .string("vivid"), "captionPreset": .string("nope"),
                ])])
            }),
            ("wrong schema version", { $0["schema"] = .string("bashcut.project/9") }),
        ]
        for (name, mutate) in cases {
            var project = base
            mutate(&project)
            #expect(throws: ProjectError.self, "\(name): validate()") { try project.validate() }
            #expect(try !checker.errors(json(project)).isEmpty, "\(name): schema")
        }
    }

    @Test("Item properties validate from one declaration")
    func declaredProperties() throws {
        let project = try richProject()
        for property in ItemProperty.all {
            var outOfRange = project
            let bad: JSONValue = switch property.rule {
            case .number(let range): .number(range.upperBound + 1)
            case .integer(let range): .integer(range.upperBound + 1)
            case .boolean: .string("yes")
            case .text(let maxLength): .string(String(repeating: "x", count: maxLength + 1))
            case .color: .string("yellow")
            }
            Self.editItem(&outOfRange, "left") { item in
                if let group = property.group {
                    var values = item[group]?.object ?? [:]
                    values[property.key] = bad
                    item[group] = .object(values)
                } else {
                    item[property.key] = bad
                }
            }
            #expect(throws: ProjectError.self, "\(property.key)") { try outOfRange.validate() }
        }
    }

    private func json(_ project: Project) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(project))
    }

    private static func editItem(_ project: inout Project, _ id: String, _ change: (inout Item) -> Void) {
        var tracks = project.tracks
        for trackIndex in tracks.indices {
            var items = tracks[trackIndex].items
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            change(&items[index])
            tracks[trackIndex].items = items
        }
        project.tracks = tracks
    }

    /// A project that uses every catalog and layer kind.
    private func richProject() throws -> Project {
        var project = try ProjectFixtures.twoClips()
        var caption = Item(id: "cap", at: 0, duration: 30)
        caption["text"] = .string("Xin chào")
        caption["textPreset"] = .string("hook-title")
        caption["textStyle"] = .object(["size": .number(0.07)])
        let lut = ColorLUT(id: "warm", name: "Warm", path: "luts/warm.cube", size: 33)
        project = try project.applying(.group(label: "Fixture", author: .user, ops: [
            .insert(track: "t1", item: caption),
            .addColorLUT(lut),
            .setProperties(item: "left", patch: ["opacity": .number(0.5), "transform": .object(["zoom": .number(1.2)])]),
            .upsertSection(id: "hook", label: "Hook", atFrame: 0),
            .upsertTransition(id: "cut", kind: "dissolve", from: "left", to: "right", duration: 10),
        ])).project
        project = try project.applying(project.savingLook(
            ColorLook(id: "warm-film", title: "Warm film", color: ["lut": .string("warm"), "lutStrength": .number(0.7)]))).project
        project = try project.applying(project.savingStyleKit(
            StyleKit(id: "street", title: "Street food", lookID: "warm-film", captionPreset: "bold-outline"))).project
        var planner = LayerPlanner(project)
        try planner.placeAdjustment(.adjustment(id: "grade", at: 0, duration: 60, color: ["exposure": .number(0.2)]))
        return planner.project
    }
}

/// The subset of JSON Schema 2020-12 that ProjectSchema uses, enough to check documents in tests.
struct SchemaChecker {
    let root: JSONValue
    init(_ root: JSONValue) { self.root = root }

    func resolve(_ ref: String) -> JSONValue? {
        guard ref.hasPrefix("#/") else { return nil }
        var node: JSONValue? = root
        for part in ref.dropFirst(2).split(separator: "/") { node = node?.object[String(part)] }
        return node
    }

    func errors(_ value: JSONValue) -> [String] { errors(value, root, "$") }

    // A schema keyword checker is inherently one switch per keyword.
    // swiftlint:disable:next cyclomatic_complexity
    private func errors(_ value: JSONValue, _ schema: JSONValue, _ path: String) -> [String] {
        let rules = schema.object
        if let ref = rules["$ref"]?.string {
            guard let target = resolve(ref) else { return ["\(path): unresolved \(ref)"] }
            return errors(value, target, path)
        }
        var found: [String] = []
        if let types = rules["type"] {
            let allowed = types.string.map { [$0] } ?? types.array.compactMap(\.string)
            if !allowed.contains(where: { matches(value, type: $0) }) { return ["\(path): expected \(allowed)"] }
        }
        if let constant = rules["const"], constant != value { found.append("\(path): expected \(constant)") }
        if let options = rules["enum"]?.array, !options.contains(value) { found.append("\(path): not in enum") }
        if case .string(let text) = value {
            if let minimum = rules["minLength"]?.int, text.count < minimum { found.append("\(path): too short") }
            if let maximum = rules["maxLength"]?.int, text.count > maximum { found.append("\(path): too long") }
            if let pattern = rules["pattern"]?.string, text.range(of: pattern, options: .regularExpression) == nil {
                found.append("\(path): does not match \(pattern)")
            }
        }
        if let number = value.double, value.int != nil || { if case .number = value { true } else { false } }() {
            if let minimum = rules["minimum"]?.double, number < minimum { found.append("\(path): below \(minimum)") }
            if let maximum = rules["maximum"]?.double, number > maximum { found.append("\(path): above \(maximum)") }
        }
        if case .object(let fields) = value {
            for key in rules["required"]?.array.compactMap(\.string) ?? [] where fields[key] == nil {
                found.append("\(path).\(key): required")
            }
            for (key, property) in rules["properties"]?.object ?? [:] {
                if let child = fields[key] { found += errors(child, property, "\(path).\(key)") }
            }
            if case .object = rules["additionalProperties"] ?? .null, let extra = rules["additionalProperties"] {
                let declared = Set((rules["properties"]?.object ?? [:]).keys)
                for (key, child) in fields where !declared.contains(key) { found += errors(child, extra, "\(path).\(key)") }
            }
        }
        if case .array(let values) = value {
            if let minimum = rules["minItems"]?.int, values.count < minimum { found.append("\(path): too few items") }
            if let maximum = rules["maxItems"]?.int, values.count > maximum { found.append("\(path): too many items") }
            let prefix = rules["prefixItems"]?.array ?? []
            for (index, child) in values.enumerated() {
                if index < prefix.count {
                    found += errors(child, prefix[index], "\(path)[\(index)]")
                } else if let items = rules["items"] {
                    found += errors(child, items, "\(path)[\(index)]")
                }
            }
        }
        for part in rules["allOf"]?.array ?? [] { found += errors(value, part, path) }
        if let options = rules["anyOf"]?.array, !options.contains(where: { errors(value, $0, path).isEmpty }) {
            found.append("\(path): matches no anyOf branch")
        }
        if let negated = rules["not"], errors(value, negated, path).isEmpty { found.append("\(path): matches not") }
        if let condition = rules["if"], errors(value, condition, path).isEmpty, let then = rules["then"] {
            found += errors(value, then, path)
        }
        return found
    }

    private func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null),
            ("integer", .integer), ("number", .integer), ("number", .number):
            true
        default: false
        }
    }
}
