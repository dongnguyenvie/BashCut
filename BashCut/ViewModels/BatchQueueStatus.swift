import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// What the queue shows for one item: the step it is on (or stopped at), its progress and its result, with review
/// issues and failures marked for attention.
struct BatchQueueStatus {
    let step: Int?
    let progress: Double
    let result: String
    let attention: Bool

    @MainActor init(item: BatchItemStatus, jobs: JobCenter) {
        let total = max(1, item.steps.count)
        let done = item.steps.filter { $0.state == .completed }.count
        let running = item.currentStep.flatMap { item.steps[$0].job }.flatMap { jobs.job($0)?.progress } ?? 0
        progress = min(1, (Double(done) + running) / Double(total))
        step = item.currentStep ?? item.steps.lastIndex { $0.state == .failed } ?? (item.state == .completed ? total - 1 : nil)
        let issues = Self.reviewIssues(item)
        switch item.state {
        case .completed:
            var parts: [String] = []
            if !item.outputs.isEmpty {
                parts.append(item.outputs.count == 1 ? String(localized: "1 file")
                             : String(format: String(localized: "%lld files"), item.outputs.count))
            }
            if let issues {
                parts.append(issues == 1 ? String(localized: "1 review issue")
                             : String(format: String(localized: "%lld review issues"), issues))
            }
            result = ([String(localized: "Done")] + parts).joined(separator: " · ")
            attention = (issues ?? 0) > 0
        case .failed:
            result = item.error.map { BatchMessage.localized($0) } ?? String(localized: "Failed")
            attention = true
        case .running:
            result = String(localized: "Running")
            attention = false
        default:
            result = item.error.map { BatchMessage.localized($0) } ?? Self.stateTitle(item.state)
            attention = false
        }
    }

    /// A batch or item state as the queue names it.
    static func stateTitle(_ state: BatchState) -> String {
        switch state {
        case .awaitingApproval: String(localized: "Awaiting approval")
        case .waiting: String(localized: "Waiting")
        case .running: String(localized: "Running")
        case .completed: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .skipped: String(localized: "Skipped")
        case .cancelled: String(localized: "Cancelled")
        case .denied: String(localized: "Denied")
        case .interrupted: String(localized: "Interrupted")
        }
    }

    /// A run's state, counts and time, as the queue's header shows them.
    static func summary(_ run: BatchRunStatus, now: Date = Date()) -> String {
        let done = run.count(.completed), total = run.items.count
        var parts = [Self.stateTitle(run.state), String(format: String(localized: "%lld of %lld done"), done, total)]
        if run.count(.failed) > 0 { parts.append(String(format: String(localized: "%lld failed"), run.count(.failed))) }
        let elapsed = run.elapsed(now: now)
        if elapsed >= 1, let text = duration(elapsed) { parts.append(String(format: String(localized: "%@ elapsed"), text)) }
        if let remaining = run.remaining(now: now), let text = duration(max(60, remaining)) {
            parts.append(String(format: String(localized: "about %@ left"), text))
        }
        return parts.joined(separator: " · ")
    }

    /// `1 hr, 5 min`, `12 min`, `40 sec` (in the app's language).
    static func duration(_ seconds: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute] : [.second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds)
    }

    /// The issues the item's last review step found: `review run` gives a list, or `{issues, summary}`; long lists
    /// are kept as their count.
    static func reviewIssues(_ item: BatchItemStatus) -> Int? {
        guard let review = item.steps.last(where: { $0.action == "review.run" && $0.state == .completed }) else {
            return nil
        }
        let issues = review.result.object["issues"] ?? review.result
        switch issues {
        case .array(let list): return list.count
        case .integer(let count): return count
        default: return nil
        }
    }
}
