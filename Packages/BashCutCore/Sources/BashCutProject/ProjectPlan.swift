import Foundation

/// What the edit is for and how the agent means to make it, as project data (P1-D1, P1-D2): the brief (goal,
/// audience, outputs, angle, length, ideas and references, each field stated by the user, inferred by the agent or
/// confirmed) and the edit plan (mode, stage, sections with ranges and reasons, shot rows, script beats, decisions,
/// frozen sections and the ranges chosen for the review profile). Both are saved with the project, so an agent can
/// resume from them alone. Both are free JSON; core reads only the few fields review uses, when present.
public enum ProjectPlan {
    /// Brief and plan are free JSON objects: the agent's notes, never validated on load (an unknown field must not
    /// block a project). Only the setter checks that each is an object or null.
    public static func validateNotes(_ value: JSONValue, key: String) throws {
        switch value {
        case .object, .null: return
        default: throw ProjectError.invalid("\(key): expected an object")
        }
    }

    /// `{min, max}` read from `value` itself or its `value` field (the stated/inferred wrapper), when both are numbers.
    public static func range(_ value: JSONValue?) -> (min: Double, max: Double)? {
        guard let value else { return nil }
        let fields = value.object["value"]?.object ?? value.object
        guard let low = fields["min"]?.double, let high = fields["max"]?.double else { return nil }
        return (low, high)
    }

    /// A list of strings read from `value` itself or its `value` field.
    public static func strings(_ value: JSONValue?) -> [String]? {
        guard let value else { return nil }
        if let list = value.object["value"]?.array { return list.compactMap(\.string) }
        if case .array(let list) = value { return list.compactMap(\.string) }
        return nil
    }

    /// A short summary for `context.get`: the brief's goal and outputs with their status, and the plan's mode, stage,
    /// section and shot counts, frozen sections, and what a recipe wrote: `recipe` (its skill), `promise`, the count
    /// of `checks`, `requiredStages` and `naStages` (stages marked `required: false`).
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
            // What a recipe wrote (spec 13 §4), so its rules survive a context reset without re-reading it.
            if let recipe = plan["recipe"]?.object["skill"] { row["recipe"] = recipe }
            if let promise = plan["promise"], promise != .null { row["promise"] = promise }
            if let checks = plan["checks"]?.array { row["checks"] = .integer(checks.count) }
            let stages = plan["stages"]?.object ?? [:]
            let required = stages.filter { $0.value.object["required"] == .bool(true) }.keys.sorted()
            let skipped = stages.filter { $0.value.object["required"] == .bool(false) }.keys.sorted()
            if !required.isEmpty { row["requiredStages"] = .array(required.map(JSONValue.string)) }
            if !skipped.isEmpty { row["naStages"] = .array(skipped.map(JSONValue.string)) }
            result["plan"] = .object(row)
        }
        return .object(result)
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
        if let length = ProjectPlan.range(brief["lengthSeconds"]), seconds < length.min || seconds > length.max {
            issues.append(
                ReviewIssue(
                    id: "brief-length", title: "Length outside the brief",
                    detail: String(format: "The brief asks %.0f–%.0f s; the edit runs %.1f s.", length.min, length.max, seconds),
                    frame: 0, severity: .info))
        }
        if let outputs = ProjectPlan.strings(brief["outputs"]), !outputs.isEmpty,
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
            guard let length = ProjectPlan.range(section["lengthSeconds"]),
                let index = markers.firstIndex(where: { $0.id == section["id"]?.string || $0.label == section["label"]?.string })
            else { continue }
            let end = index + 1 < markers.count ? markers[index + 1].at : project.duration
            let measured = Double(end - markers[index].at) / fps
            guard measured < length.min || measured > length.max else { continue }
            let label = section["label"]?.string ?? markers[index].label
            issues.append(
                ReviewIssue(
                    id: "plan-section-" + (section["id"]?.string ?? markers[index].id), title: "Section \(label) off plan",
                    detail: String(format: "Planned %.0f–%.0f s, measured %.1f s.", length.min, length.max, measured),
                    frame: markers[index].at, endFrame: end, severity: .info))
        }
        return issues
    }
}
