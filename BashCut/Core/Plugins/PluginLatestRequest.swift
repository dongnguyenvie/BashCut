import Foundation

/// Runs only the newest of rapid requests (a plugin view that follows the selection, #405). Each `schedule` replaces
/// one still waiting; it starts after `delay` without a newer one and cancels the request still running (whose plugin
/// gets `cancel`), then waits for it to end, so the plugin has one render at a time and never renders an item the user
/// already left.
@MainActor public final class PluginLatestRequest {
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?
    /// Requests that started (for benchmarks and tests).
    public private(set) var started = 0

    public init() {}

    /// Whether a request waits or runs.
    public var isActive: Bool { pending != nil || running != nil }

    public func schedule(after delay: Duration, _ work: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            let previous = self.running
            previous?.cancel()
            self.started += 1
            let task = Task { @MainActor in
                await previous?.value
                if !Task.isCancelled { await work() }
            }
            self.running = task
            await task.value
            // Only the newest request clears itself; an older one finishing must not forget a newer one.
            if self.running == task { self.running = nil }
        }
    }

    /// Drops the waiting request and cancels the running one.
    public func cancel() {
        pending?.cancel()
        pending = nil
        running?.cancel()
        running = nil
    }
}
