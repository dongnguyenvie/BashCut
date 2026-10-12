import Foundation

/// Where an agent's run is (#447), read from the run log's `stage` entries of the current run: the stages to show,
/// the one in progress with its step text, progress and ETA, and when the run and each stage started. BashCut writes
/// the stages it can prove itself (`plan apply`, a passing review, an export); the agent adds the rest with one
/// `run progress <stage>` call per stage. Nothing here judges the edit: it only reports what was logged.
public struct RunProgress: Equatable, Sendable {
    public enum Status: String, Sendable { case pending, active, started, done, skipped }

    public struct Stage: Equatable, Sendable {
        public let id: String
        public var status: Status
        public var startedAt: Date?
        public var endedAt: Date?
        public var text: String?
    }

    /// The run number (`RunLog` numbers them; 0 before the first `start`).
    public let run: Int
    public let startedAt: Date?
    /// The `end` entry's time, when the agent closed the run.
    public let endedAt: Date?
    public let stages: [Stage]
    /// The stage in progress: the latest stage entry when it is not done or skipped.
    public let current: String?
    public let text: String?
    /// 0…1, as the agent reported it for the current stage.
    public let progress: Double?
    /// Seconds left as the agent estimated them at `updatedAt`.
    public let eta: Double?
    public let updatedAt: Date?
    /// When the export stage was last done in this run: the result card shows from then on.
    public let exportedAt: Date?
    /// The latest stage entry's time: a stage reported after it shows a closed panel again.
    public let lastActivity: Date?

    /// The stages the panel shows besides any the run or the plan adds: the ticket's survey → export.
    public static let shownStages = ["survey", "story", "rough-cut", "sound", "captions", "colour", "effects", "review", "export"]
    /// Short names agents may use for a stage ID.
    public static let aliases = ["cut": "rough-cut", "roughcut": "rough-cut", "color": "colour", "audio": "sound",
                                 "text": "captions", "fx": "effects"]

    /// The stage ID for a name an agent typed: `cut` → `rough-cut`, `color` → `colour`.
    public static func stageID(_ name: String) -> String {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return aliases[key] ?? key
    }

    /// The progress of the current run, or nil when it has no stage entry yet.
    public static func make(_ project: Project, entries all: [[String: JSONValue]]) -> RunProgress? {
        let entries = WorkflowChecklist.currentRun(all)
        let stageEntries = entries.filter { $0["kind"]?.string == "stage" && $0["stage"]?.string != nil }
        guard !stageEntries.isEmpty else { return nil }
        let planStages = project["plan"]?.object["stages"]?.object ?? [:]
        let logged = Set(stageEntries.compactMap { $0["stage"]?.string })
        let table = WorkflowChecklist.stageTable(planStages).map(\.id).filter { id in
            let notRequired = planStages[id]?.object["required"]?.bool == false
            if logged.contains(id) { return true }
            if notRequired { return false }
            return shownStages.contains(id) || planStages[id] != nil
        }
        // Stages only the log names (a plan changed since) go before review, like the checklist puts them.
        let extra = logged.subtracting(table).sorted()
        var ids = table
        ids.insert(contentsOf: extra, at: ids.firstIndex(of: "review") ?? ids.count)
        let latest = stageEntries.last
        let currentID = latest.flatMap { entry -> String? in
            let status = entry["status"]?.string ?? "started"
            return ["done", "skipped"].contains(status) ? nil : entry["stage"]?.string
        }
        let stages = ids.map { id -> Stage in
            let rows = stageEntries.filter { $0["stage"]?.string == id }
            guard let last = rows.last else { return Stage(id: id, status: .pending) }
            let status: Status = switch last["status"]?.string ?? "started" {
            case "done": .done
            case "skipped": .skipped
            default: id == currentID ? .active : .started
            }
            let ended = [.done, .skipped].contains(status) ? date(last) : nil
            return Stage(id: id, status: status, startedAt: rows.first.flatMap(date), endedAt: ended, text: last["text"]?.string)
        }
        let start = entries.last { $0["kind"]?.string == "start" } ?? entries.first
        let end = entries.last { $0["kind"]?.string == "end" }
        let exported = stageEntries.last { $0["stage"]?.string == "export" && $0["status"]?.string == "done" }
        let currentEntry = currentID == nil ? nil : latest
        return RunProgress(
            run: entries.last?["run"]?.int ?? 0, startedAt: start.flatMap(date), endedAt: end.flatMap(date), stages: stages,
            current: currentID, text: currentEntry?["text"]?.string,
            progress: currentEntry?["progress"]?.double.map { min(1, max(0, $0)) },
            eta: currentEntry?["eta"]?.double.map { max(0, $0) }, updatedAt: currentEntry.flatMap(date),
            exportedAt: exported.flatMap(date), lastActivity: latest.flatMap(date))
    }

    /// Whether the run is over: the agent ended it, or it exported and nothing started after the export.
    public var finished: Bool { endedAt != nil || (exportedAt != nil && current == nil) }

    /// Seconds since the run started, up to its end.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Seconds the current stage has taken so far.
    public func stageElapsed(now: Date = Date()) -> TimeInterval? {
        guard let current, let stage = stages.first(where: { $0.id == current }), let startedAt = stage.startedAt else {
            return nil
        }
        return max(0, now.timeIntervalSince(startedAt))
    }

    /// The agent's ETA counted down since it was reported; nil without one.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let eta, let updatedAt else { return nil }
        return max(0, eta - now.timeIntervalSince(updatedAt))
    }

    /// `run.status`'s `progress`.
    public func json(now: Date = Date()) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        func time(_ date: Date?) -> JSONValue { date.map { .string(formatter.string(from: $0)) } ?? .null }
        func seconds(_ value: TimeInterval?) -> JSONValue { value.map { .integer(Int($0.rounded())) } ?? .null }
        let rows = stages.map { stage -> JSONValue in
            var row: [String: JSONValue] = ["id": .string(stage.id), "status": .string(stage.status.rawValue)]
            if let start = stage.startedAt {
                row["seconds"] = seconds((stage.endedAt ?? (stage.status == .active ? now : nil)).map { $0.timeIntervalSince(start) })
            }
            if let text = stage.text { row["text"] = .string(text) }
            return .object(row)
        }
        return .object([
            "run": .integer(run), "startedAt": time(startedAt), "elapsed": seconds(elapsed(now: now)),
            "current": current.map(JSONValue.string) ?? .null, "text": text.map(JSONValue.string) ?? .null,
            "progress": progress.map(JSONValue.number) ?? .null, "remaining": seconds(remaining(now: now)),
            "stageElapsed": seconds(stageElapsed(now: now)), "finished": .bool(finished),
            "exportedAt": time(exportedAt), "stages": .array(rows),
        ])
    }

    private static func date(_ entry: [String: JSONValue]) -> Date? {
        entry["time"]?.string.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}
