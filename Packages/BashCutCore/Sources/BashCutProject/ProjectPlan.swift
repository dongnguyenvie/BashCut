import Foundation

/// What the edit is for and how the agent means to make it, as project data (P1-D1, P1-D2): the brief (goal,
/// audience, outputs, angle, length, ideas and references, each field stated by the user, inferred by the agent or
/// confirmed) and the edit plan (mode, stage, sections with ranges and reasons, shot rows, script beats, decisions,
/// frozen sections and the ranges chosen for the review profile). Both are saved with the project, so an agent can
/// resume from them alone. Core checks their shape, not their content.
public enum ProjectPlan {
    public static let statuses = ["stated", "inferred", "confirmed"]
    public static let briefFields = ["goal", "audience", "outputs", "angle", "lengthSeconds", "notes"]
    public static let modes = ["create", "directed", "revision"]
    public static let shotSources = ["footage", "stock", "generated"]

    // MARK: Brief

    /// A brief field: `{value, status, source?}`.
    static func validateField(_ value: JSONValue, path: String) throws {
        let fields = value.object
        guard case .object = value, fields["value"] != nil,
            fields["status"]?.string.map(statuses.contains) == true,
            Set(fields.keys).isSubset(of: ["value", "status", "source"])
        else { throw ProjectError.invalid("\(path): expected {value, status stated|inferred|confirmed, source?}") }
    }

    public static func validateBrief(_ value: JSONValue) throws {
        guard case .object(let brief) = value else { throw ProjectError.invalid("brief: expected object") }
        for key in brief.keys.sorted() {
            switch key {
            case _ where briefFields.contains(key): try validateField(brief[key] ?? .null, path: "brief.\(key)")
            case "ideas", "references":
                guard case .array(let list)? = brief[key], list.count <= 100,
                    list.allSatisfy({ if case .object = $0 { return true } else { return false } })
                else { throw ProjectError.invalid("brief.\(key): expected up to 100 objects") }
            default: throw ProjectError.invalid("brief: unknown field \(key)")
            }
        }
    }

    // MARK: Plan

    public static func validatePlan(_ value: JSONValue) throws {
        guard case .object(let plan) = value else { throw ProjectError.invalid("plan: expected object") }
        let allowed: Set<String> = ["mode", "stage", "options", "sections", "shots", "beats", "decisions", "ranges", "notes"]
        if let unknown = plan.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw ProjectError.invalid("plan: unknown field \(unknown)")
        }
        if let mode = plan["mode"], mode.string.map(modes.contains) != true {
            throw ProjectError.invalid("plan.mode: expected \(modes.joined(separator: ", "))")
        }
        let sections = try rows(plan["sections"], path: "plan.sections", required: ["id", "label"])
        for (index, section) in sections.enumerated() {
            if let length = section["lengthSeconds"] { try validateRange(length, path: "plan.sections[\(index)].lengthSeconds") }
        }
        guard Set(sections.compactMap { $0["id"]?.string }).count == sections.count else {
            throw ProjectError.invalid("plan.sections: IDs must be unique")
        }
        try validateShots(plan["shots"])
        _ = try rows(plan["beats"], path: "plan.beats", required: ["id", "text"])
        _ = try rows(plan["decisions"], path: "plan.decisions", required: ["text"])
        if let ranges = plan["ranges"] {
            guard case .object(let map) = ranges else { throw ProjectError.invalid("plan.ranges: expected object") }
            for (key, range) in map { try validateRange(range, path: "plan.ranges.\(key)") }
        }
    }

    /// Shot rows: `id` and `purpose`, an optional known size and source, `mustShow` as names.
    static func validateShots(_ value: JSONValue?) throws {
        let shots = try rows(value, path: "plan.shots", required: ["id", "purpose"])
        for (index, shot) in shots.enumerated() {
            if let size = shot["size"], size.string.map(MediaDescription.sizes.contains) != true {
                throw ProjectError.invalid("plan.shots[\(index)].size: expected \(MediaDescription.sizes.joined(separator: ", "))")
            }
            if let source = shot["source"], source.string.map(shotSources.contains) != true {
                throw ProjectError.invalid("plan.shots[\(index)].source: expected \(shotSources.joined(separator: ", "))")
            }
            if let tags = shot["mustShow"] {
                guard case .array(let list) = tags, list.allSatisfy({ $0.string != nil }) else {
                    throw ProjectError.invalid("plan.shots[\(index)].mustShow: expected names")
                }
            }
        }
    }

    /// `{min, max, source?, reason?}` with min ≤ max.
    static func validateRange(_ value: JSONValue, path: String) throws {
        let fields = value.object
        guard let low = fields["min"]?.double, let high = fields["max"]?.double, low.isFinite, high.isFinite, low <= high
        else { throw ProjectError.invalid("\(path): expected {min, max} with min ≤ max") }
    }

    /// The objects of an optional list, each with `required` keys, at most 500.
    static func rows(_ value: JSONValue?, path: String, required: [String]) throws -> [[String: JSONValue]] {
        guard let value, value != .null else { return [] }
        guard case .array(let list) = value, list.count <= 500 else { throw ProjectError.invalid("\(path): expected a list") }
        return try list.enumerated().map { index, row in
            guard case .object(let fields) = row, required.allSatisfy({ fields[$0] != nil }) else {
                throw ProjectError.invalid("\(path)[\(index)]: expected an object with \(required.joined(separator: ", "))")
            }
            return fields
        }
    }

    /// A short summary for `context.get`: the brief's goal and outputs with their status, and the plan's mode, stage,
    /// section and shot counts and frozen sections.
    public static func summary(_ project: Project) -> JSONValue {
        var result: [String: JSONValue] = [:]
        if let brief = project["brief"]?.object {
            result["brief"] = .object(brief.filter { ["goal", "outputs", "lengthSeconds"].contains($0.key) })
        }
        if let plan = project["plan"]?.object {
            let sections: [JSONValue] = plan["sections"]?.array ?? []
            let frozen: [JSONValue] = sections.filter { $0.object["frozen"] == .bool(true) }.compactMap { $0.object["id"] }
            let shots: Int = plan["shots"]?.array.count ?? 0
            let beats: Int = plan["beats"]?.array.count ?? 0
            var row: [String: JSONValue] = ["sections": .integer(sections.count), "shots": .integer(shots)]
            row["mode"] = plan["mode"] ?? .null
            row["stage"] = plan["stage"] ?? .null
            row["beats"] = .integer(beats)
            row["frozen"] = .array(frozen)
            result["plan"] = .object(row)
        }
        return .object(result)
    }
}

extension Project {
    /// `brief` and `plan`, when present.
    func validatePlanSettings() throws {
        if let brief = self["brief"], brief != .null { try ProjectPlan.validateBrief(brief) }
        if let plan = self["plan"], plan != .null { try ProjectPlan.validatePlan(plan) }
    }
}

extension TimelineReview {
    /// The brief and plan against what was measured (P1-D1, P1-D3), as info: the edit's length against the brief's
    /// length range, the brief's outputs against `output.presets`, and each planned section's length range against
    /// the span of its section marker (matched by ID or label).
    static func planIssues(_ project: Project) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let fps = project.fps.value
        let seconds = Double(project.duration) / fps
        let brief = project["brief"]?.object ?? [:]
        if let range = brief["lengthSeconds"]?.object["value"]?.object, let low = range["min"]?.double,
            let high = range["max"]?.double, seconds < low || seconds > high
        {
            issues.append(
                ReviewIssue(
                    id: "brief-length", title: "Length outside the brief",
                    detail: String(format: "The brief asks %.0f–%.0f s; the edit runs %.1f s.", low, high, seconds),
                    frame: 0, severity: .info))
        }
        if let outputs = brief["outputs"]?.object["value"]?.array.compactMap(\.string), !outputs.isEmpty,
            Set(outputs) != Set(project.outputPresets)
        {
            issues.append(
                ReviewIssue(
                    id: "brief-outputs", title: "Outputs differ from the brief",
                    detail: "The brief names \(outputs.joined(separator: ", ")); output.presets is "
                        + "\(project.outputPresets.isEmpty ? "empty" : project.outputPresets.joined(separator: ", ")).",
                    frame: 0, severity: .info, fix: ReviewFix(command: "project.format", arguments: [
                        "outputs": .string(outputs.joined(separator: ",")),
                    ])))
        }
        let markers = project.sectionMarkers
        for section in project["plan"]?.object["sections"]?.array.map(\.object) ?? [] {
            guard let range = section["lengthSeconds"]?.object, let low = range["min"]?.double, let high = range["max"]?.double,
                let index = markers.firstIndex(where: { $0.id == section["id"]?.string || $0.label == section["label"]?.string })
            else { continue }
            let end = index + 1 < markers.count ? markers[index + 1].at : project.duration
            let measured = Double(end - markers[index].at) / fps
            guard measured < low || measured > high else { continue }
            let label = section["label"]?.string ?? markers[index].label
            issues.append(
                ReviewIssue(
                    id: "plan-section-" + (section["id"]?.string ?? markers[index].id), title: "Section \(label) off plan",
                    detail: String(format: "Planned %.0f–%.0f s, measured %.1f s.", low, high, measured),
                    frame: markers[index].at, endFrame: end, severity: .info))
        }
        return issues
    }
}
