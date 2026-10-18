import Foundation

/// A run's time estimate, its retry and what quitting does to it.
extension BatchRunStatus {
    /// Items a finished run can run again: failed, cancelled, skipped, interrupted or never started.
    public var retryableItems: [Int] {
        guard state.isFinished else { return [] }
        return items.indices.filter { [.failed, .cancelled, .skipped, .interrupted, .waiting].contains(items[$0].state) }
    }

    /// Seconds since the run (or its latest retry) started running, up to when it finished.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        guard let runningSince else { return 0 }
        return max(0, (finishedAt ?? now).timeIntervalSince(runningSince))
    }

    /// Seconds left while it runs: the average time of the items this run finished (completed ones when there are
    /// any) times the items still waiting, plus what is left of the running one. Nil before the first item ends.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard state == .running, let since = runningSince else { return nil }
        let ended = items.filter { item in
            guard let start = item.startedAt, let end = item.finishedAt else { return false }
            return start >= since && end >= start && [.completed, .failed].contains(item.state)
        }
        let completed = ended.filter { $0.state == .completed }
        let sample = completed.isEmpty ? ended : completed
        guard !sample.isEmpty else { return nil }
        let average = sample.reduce(0.0) { $0 + ($1.finishedAt ?? now).timeIntervalSince($1.startedAt ?? now) }
            / Double(sample.count)
        let current = items.first { $0.state == .running }.map { item in
            max(0, average - now.timeIntervalSince(item.startedAt ?? now))
        } ?? 0
        return average * Double(count(.waiting)) + current
    }

    /// Items done or failed out of all, for an overall progress bar (0…1).
    public var fractionDone: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.state.isFinished }.count) / Double(items.count)
    }

    /// Sets `indices` (default: every retryable item) to run again: steps that completed are kept, so each item goes
    /// on from the step that failed in the project it already made. False when there is nothing to retry.
    @discardableResult
    public mutating func prepareRetry(_ indices: [Int]? = nil) -> Bool {
        let chosen = Set(indices ?? retryableItems).intersection(retryableItems)
        guard !chosen.isEmpty else { return false }
        for index in chosen {
            items[index].state = .waiting
            items[index].error = nil
            items[index].currentStep = nil
            for step in items[index].steps.indices where items[index].steps[step].state != .completed {
                items[index].steps[step].state = .waiting
                items[index].steps[step].error = nil
                items[index].steps[step].errorCategory = nil
                items[index].steps[step].job = nil
            }
        }
        state = .waiting
        error = nil
        finishedAt = nil
        runningSince = nil
        return true
    }

    /// Marks a run that was not finished as interrupted (BashCut quit or stopped while it ran), so `batch retry` can
    /// go on from there. The item that was running runs all its steps again: they were not saved (the runner saves an
    /// item's project when its steps end), so it starts over in the project it made.
    public mutating func markInterrupted(at date: Date = Date()) {
        guard !state.isFinished || state == .interrupted else { return }
        for index in items.indices where items[index].state == .running {
            items[index].state = .interrupted
            items[index].currentStep = nil
            items[index].finishedAt = date
            for step in items[index].steps.indices {
                items[index].steps[step].state = .waiting
                items[index].steps[step].job = nil
                items[index].steps[step].result = .null
            }
        }
        state = .interrupted
        finishedAt = finishedAt ?? date
    }
}
