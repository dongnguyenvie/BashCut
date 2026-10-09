import CryptoKit
import Foundation

/// The run's checklist (spec 13 §5), derived from the plan and the run log, never hand-written: each stage of the
/// kit's table with its skill, whether that skill was read (written by BashCut or the kit hook), the agent's status,
/// evidence and reason, the recipe's `required` and `n/a`, the three audits (§6.2) and what is still open. Also the
/// two guards of §7 that agent authors meet before G2 and a final export.
public enum WorkflowChecklist {
    /// The fixed stage IDs and each one's default skill (the kit's stage table).
    public static let stages: [(id: String, skill: String)] = [
        ("intake", "bc:edit-workflow"), ("survey", "bc:footage-survey"), ("story", "bc:edit-workflow"),
        ("rough-cut", "bc:rough-cut"), ("rhythm", "bc:beat-cut"), ("voiceover", "bc:voiceover"),
        ("sound", "bc:audio-mix"), ("captions", "bc:captions-text"), ("colour", "bc:color-grade"),
        ("effects", "bc:effects"), ("review", "bc:review"), ("export", "bc:edit-workflow"), ("learn", "bc:self-learn"),
    ]
    /// Default skills of stages a plan may add besides the fixed ones (a plan stage's `skill` wins).
    static let extraSkills = [
        "motion-graphics": "bc:motion-graphics", "stock": "bc:stock-images", "stock-images": "bc:stock-images",
        "library": "bc:library", "visuals": "bc:visual-plan",
    ]
    /// Stages every edit goes through unless the plan marks one `required: false`.
    public static let requiredByDefault: Set<String> = ["intake", "survey", "story", "rough-cut", "review", "export"]
    public static let auditPoints = ["strategy", "draft", "process"]
    public static let verdicts = ["pass", "changes", "fail"]
    public static let auditors = ["critic", "self"]
    public static let stageStatuses = ["done", "skipped"]

    /// The kit's generic checks (§6.2), added to every video's draft and strategy audit before a recipe's own.
    public static let genericChecks: [JSONValue] = [
        ("one-message", "The video says one thing"),
        ("promise", "promise.payoff answers promise.hook"),
        ("first-3s", "Text and speech in the first 3 s say the same thing"),
        ("sound-off", "Understandable with sound off"),
        ("captions-not-text", "Captions never repeat on-screen text"),
        ("nothing-unasked", "Nothing on screen the brief did not ask for (credits off by default)"),
    ].map { .object(["id": .string($0.0), "text": .string($0.1), "source": .string("kit")]) }

    // MARK: Run log

    /// The entries of the current run: from the last `start` on (all of them before the first start). `RunLog`
    /// numbers runs in `run`; entries without it count as one run.
    public static func currentRun(_ entries: [[String: JSONValue]]) -> [[String: JSONValue]] {
        guard let last = entries.last?["run"]?.int else { return entries }
        return entries.filter { $0["run"]?.int == last }
    }

    /// A skill name as the checklist compares it: kit skills read through `skills get` are logged bare
    /// (`rough-cut`) and the hook logs Claude Code's name (`bc:rough-cut`); both become `bc:rough-cut`.
    public static func skillName(_ name: String, origin: String?) -> String {
        origin == "kit" && !name.hasPrefix("bc:") ? "bc:" + name : name
    }

    /// The skill entries that read `skill`, oldest first.
    static func reads(of skill: String, in entries: [[String: JSONValue]]) -> [[String: JSONValue]] {
        entries.filter { entry in
            entry["kind"]?.string == "skill"
                && entry["name"]?.string.map { skillName($0, origin: entry["origin"]?.string) } == skill
        }
    }

    /// What the viewer sees and hears: tracks, transitions, markers, looks, audio settings and the format. An audit
    /// stays valid while this does not change (notes such as the brief, plan or selects do not count).
    public static func timelineFingerprint(_ project: Project) -> String {
        var fields: [String: JSONValue] = [:]
        for key in ["tracks", "transitions", "markers", "luts", "audio", "format", "clipFill"] {
            fields[key] = project[key] ?? .null
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(JSONValue.object(fields))) ?? Data()
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Checklist

    /// `run.checklist`: `{stages, audits, auditDetails, recipe, open}` from the plan and the run log entries
    /// (`RunLog.entries()`; only the current run counts, but a recipe read in an earlier run still counts).
    public static func json(_ project: Project, entries all: [[String: JSONValue]]) -> JSONValue {
        let entries = currentRun(all)
        let plan = project["plan"]?.object ?? [:]
        let planStages = plan["stages"]?.object ?? [:]
        let recipe = plan["recipe"]?.object["skill"]?.string
        let table = stageTable(planStages)
        var open: [String] = []
        let recipeRead = recipe.map { !reads(of: $0, in: all).isEmpty }
        if let recipe, recipeRead == false { open.append("recipe \(recipe) not read (skills get \(recipe))") }
        let stageEntries = entries.filter { $0["kind"]?.string == "stage" }
        let reached = table.lastIndex { stage in stageEntries.contains { $0["stage"]?.string == stage.id } } ?? -1
        let rows = table.enumerated().map { index, stage in
            let row = stageRow(
                stage, settings: planStages[stage.id]?.object ?? [:], entries: entries, naBy: recipe == nil ? "plan" : "recipe")
            open += openPoints(row, passed: reached > index)
            return row
        }
        func reachedStage(_ ids: [String], done: Bool = false) -> Bool {
            stageEntries.contains { entry in
                ids.contains(entry["stage"]?.string ?? "") && (!done || entry["status"]?.string == "done")
            }
        }
        let due = [
            "strategy": reachedStage(["story"], done: true) || reachedStage(table.drop(while: { $0.id != "rough-cut" }).map(\.id)),
            "draft": reachedStage(["review"], done: true) || reachedStage(["export", "learn"]),
            "process": reachedStage(["learn"]) || reachedStage(["export"], done: true),
        ]
        let (verdicts, details) = auditSummary(project, entries: entries, due: due, open: &open)
        var result: [String: JSONValue] = [
            "stages": .array(rows.map(JSONValue.object)), "audits": .object(verdicts), "auditDetails": .object(details),
            "open": .array(open.map(JSONValue.string)),
        ]
        if let recipe, let recipeRead { result["recipe"] = .object(["skill": .string(recipe), "read": .bool(recipeRead)]) }
        return .object(result)
    }

    /// The kit's stages with any other stage the plan names: right after the stage its `after` names (a fixed stage
    /// or another added one; several after the same stage keep their name order), else before review. A plan puts a
    /// stage where its work belongs, such as a visual plan after the cut is locked.
    static func stageTable(_ planStages: [String: JSONValue]) -> [(id: String, skill: String)] {
        var table = stages
        let fixed = Set(stages.map(\.id))
        var pending = planStages.keys.filter { !fixed.contains($0) }.sorted()
        // Passes until nothing more can be placed, so an added stage may follow another added one.
        var placedAfter: [String: Int] = [:]
        while true {
            let placeable = pending.filter { id in
                guard let anchor = planStages[id]?.object["after"]?.string, anchor != id else { return false }
                return table.contains { $0.id == anchor }
            }
            guard !placeable.isEmpty else { break }
            for id in placeable {
                let anchor = planStages[id]?.object["after"]?.string ?? ""
                let index = (table.firstIndex { $0.id == anchor } ?? table.count - 1) + 1 + (placedAfter[anchor] ?? 0)
                table.insert((id, extraSkills[id] ?? ""), at: min(index, table.count))
                placedAfter[anchor, default: 0] += 1
            }
            pending.removeAll { placeable.contains($0) }
        }
        let reviewIndex = table.firstIndex { $0.id == "review" } ?? table.count
        table.insert(contentsOf: pending.map { ($0, extraSkills[$0] ?? "") }, at: reviewIndex)
        return table
    }

    /// One stage's row: skill and whether it was read, status, required, the entry's evidence and reason; `n/a`
    /// (by `naBy`) when the plan marks it not required and nothing was logged.
    static func stageRow(
        _ stage: (id: String, skill: String), settings: [String: JSONValue], entries: [[String: JSONValue]], naBy: String
    ) -> [String: JSONValue] {
        var row: [String: JSONValue] = ["id": .string(stage.id)]
        if let rules = settings["rules"], !rules.array.isEmpty { row["rules"] = rules }
        let entry = entries.last { $0["kind"]?.string == "stage" && $0["stage"]?.string == stage.id }
        if entry == nil, settings["required"]?.bool == false {
            row["status"] = .string("n/a")
            row["reason"] = settings["why"]
            row["by"] = .string(naBy)
            return row
        }
        if let skill = settings["skill"]?.string ?? (stage.skill.isEmpty ? nil : stage.skill) {
            let read = reads(of: skill, in: entries)
            row["skill"] = .string(skill)
            row["skillRead"] = .bool(!read.isEmpty)
            if !read.isEmpty, read.allSatisfy({ $0["verified"]?.bool == false }) { row["skillReadUnverified"] = .bool(true) }
        }
        row["status"] = .string(entry.map { $0["status"]?.string ?? "started" } ?? "pending")
        if settings["required"]?.bool ?? requiredByDefault.contains(stage.id) { row["required"] = .bool(true) }
        if let entry {
            for key in ["evidence", "reason", "unverified"] { row[key] = entry[key] }
            row["rev"] = entry["rev"] ?? .null
        }
        return row
    }

    /// What a stage row still needs: its skill read once work started, a required stage not skipped, evidence for
    /// done, and a required stage done once a later one (`passed`) has begun.
    static func openPoints(_ row: [String: JSONValue], passed: Bool) -> [String] {
        let id = row["id"]?.string ?? "", status = row["status"]?.string ?? ""
        let required = row["required"] == .bool(true)
        var open: [String] = []
        if row["skillRead"] == .bool(false), ["started", "done"].contains(status), let skill = row["skill"]?.string {
            open.append("\(id): skill \(skill) not read")
        }
        if status == "skipped", required { open.append("\(id): required stage skipped") }
        if status == "done", row["unverified"] == .bool(true) { open.append("\(id): done without evidence") }
        if ["pending", "started"].contains(status), required, passed { open.append("\(id): required stage not done") }
        return open
    }

    /// The latest verdict per audit point and its details; a missing audit that is `due`, a verdict other than pass
    /// and a stale draft audit go to `open`.
    static func auditSummary(
        _ project: Project, entries: [[String: JSONValue]], due: [String: Bool], open: inout [String]
    ) -> (verdicts: [String: JSONValue], details: [String: JSONValue]) {
        var verdicts: [String: JSONValue] = [:], details: [String: JSONValue] = [:]
        for point in auditPoints {
            guard let audit = entries.last(where: { $0["kind"]?.string == "audit" && $0["point"]?.string == point }) else {
                verdicts[point] = .null
                if due[point] == true { open.append("\(point) audit missing") }
                continue
            }
            let verdict = audit["verdict"]?.string ?? "?"
            verdicts[point] = .string(verdict)
            var detail: [String: JSONValue] = [
                "verdict": .string(verdict), "by": audit["by"] ?? .string("self"), "rev": audit["rev"] ?? .null,
            ]
            detail["findings"] = audit["findings"]
            if point == "draft" {
                let current = isCurrent(audit, project)
                detail["current"] = .bool(current)
                if !current { open.append("draft audit is older than the last edit") }
            }
            details[point] = .object(detail)
            if verdict != "pass" { open.append("\(point) audit: \(verdict)") }
        }
        return (verdicts, details)
    }

    /// Whether an audit saw the current timeline (its fingerprint, else its revision).
    static func isCurrent(_ audit: [String: JSONValue], _ project: Project) -> Bool {
        audit["timeline"]?.string.map { $0 == timelineFingerprint(project) } ?? (audit["rev"]?.int == project.revision)
    }

    /// `context.get` › `workflow.checklist`: each stage's status (`done (unverified)` without evidence), the audit
    /// verdicts and the first open points.
    public static func compact(_ checklist: JSONValue) -> JSONValue {
        let rows = checklist.object["stages"]?.array.map(\.object) ?? []
        let stages = rows.map { row -> JSONValue in
            let status = row["status"]?.string ?? "pending"
            let id = row["id"]?.string ?? ""
            return .string("\(id): \(row["unverified"] == .bool(true) ? "done (unverified)" : status)")
        }
        let open = checklist.object["open"]?.array ?? []
        return .object([
            "stages": .array(stages), "audits": checklist.object["audits"] ?? .null,
            "open": .array(Array(open.prefix(8))), "openCount": .integer(open.count),
        ])
    }

    /// `context.get` › `workflow.next`: the first stage not done, skipped or n/a, its skill and whether it was read
    /// (with the recipe when it is set and unread); null when every stage is closed.
    public static func next(_ checklist: JSONValue) -> JSONValue {
        let rows = checklist.object["stages"]?.array.map(\.object) ?? []
        guard let row = rows.first(where: { ["pending", "started"].contains($0["status"]?.string ?? "") }) else {
            return .null
        }
        var next: [String: JSONValue] = [
            "stage": row["id"] ?? .null, "skill": row["skill"] ?? .null, "skillRead": row["skillRead"] ?? .bool(false),
        ]
        if let recipe = checklist.object["recipe"]?.object, recipe["read"] == .bool(false) {
            next["recipe"] = recipe["skill"] ?? .null
        }
        return .object(next)
    }

    // MARK: Guards (§7)

    /// Why a guarded command cannot run yet: `audit_missing` or `recipe_unread`, and the command that fixes it.
    public struct GuardFailure: Error, Equatable, Sendable {
        public let category: String
        public let message: String
        public let command: String
    }

    /// Before an agent's final export: the latest draft audit passed and the timeline has not changed since, or the
    /// user approved G5 at the current revision. A self-run audit counts (decision 3).
    public static func draftGuard(_ project: Project, entries: [[String: JSONValue]]) -> GuardFailure? {
        let approved = entries.contains { entry in
            entry["kind"]?.string == "gate" && entry["gate"]?.string == "G5" && entry["event"]?.string == "approved"
                && entry["rev"]?.int == project.revision
        }
        if approved { return nil }
        let command = "review packet --point draft"
        guard let audit = entries.last(where: { $0["kind"]?.string == "audit" && $0["point"]?.string == "draft" }) else {
            return GuardFailure(
                category: "audit_missing",
                message: "A final export needs a draft audit: build the packet (review packet --point draft), have a "
                    + "fresh critic review it, then run append audit --point draft --verdict pass|changes|fail",
                command: command)
        }
        let verdict = audit["verdict"]?.string ?? "?"
        guard verdict == "pass" else {
            return GuardFailure(
                category: "audit_missing",
                message: "The latest draft audit says \(verdict): fix its findings and audit the draft again", command: command)
        }
        guard isCurrent(audit, project) else {
            return GuardFailure(
                category: "audit_missing",
                message: "The timeline changed after the draft audit (revision \(audit["rev"]?.int ?? 0)): audit the "
                    + "current draft again", command: command)
        }
        return nil
    }

    /// Before G2 (or the rough cut when G2 is skipped): the recipe skill read when the plan names one, and a
    /// strategy audit of any verdict.
    public static func strategyGuard(_ project: Project, entries: [[String: JSONValue]]) -> GuardFailure? {
        if let recipe = project["plan"]?.object["recipe"]?.object["skill"]?.string, reads(of: recipe, in: entries).isEmpty {
            return GuardFailure(
                category: "recipe_unread",
                message: "The plan's recipe \(recipe) was not read: read it (skills get \(recipe)) and apply its plan data",
                command: "skills get \(recipe)")
        }
        guard entries.contains(where: { $0["kind"]?.string == "audit" && $0["point"]?.string == "strategy" }) else {
            return GuardFailure(
                category: "audit_missing",
                message: "The strategy needs an audit before the rough cut: build the packet (review packet --point "
                    + "strategy), have a fresh critic review it, then run append audit --point strategy --verdict …",
                command: "review packet --point strategy")
        }
        return nil
    }
}
