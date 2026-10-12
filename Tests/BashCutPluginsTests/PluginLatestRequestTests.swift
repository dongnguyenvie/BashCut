import BashCutPlugins
import Foundation
import Testing

/// Inspector plugin views follow the selection through `PluginLatestRequest` (#405).
@Suite("Plugin latest request")
@MainActor struct PluginLatestRequestTests {
    @MainActor final class Log {
        var started: [Int] = []
        var finished: [Int] = []
        var cancelled: [Int] = []
        var running = 0
        var overlapped = false
    }

    private func work(_ index: Int, _ log: Log, milliseconds: Int = 40) -> @MainActor () async -> Void {
        {
            log.started.append(index)
            log.running += 1
            if log.running > 1 { log.overlapped = true }
            do {
                try await Task.sleep(for: .milliseconds(milliseconds))
                log.finished.append(index)
            } catch {
                log.cancelled.append(index)
            }
            log.running -= 1
        }
    }

    /// Waits (up to 30 s) for `condition`, so the tests hold on a busy machine.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<3000 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    private func settle(_ request: PluginLatestRequest) async throws {
        for _ in 0..<3000 where request.isActive { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!request.isActive)
    }

    @Test("Rapid changes within the debounce run only the last one")
    func debounce() async throws {
        let request = PluginLatestRequest()
        let log = Log()
        for index in 0..<50 {
            request.schedule(after: .milliseconds(100), work(index, log))
            await Task.yield()
        }
        try await settle(request)
        #expect(request.started == 1)
        #expect(log.started == [49] && log.finished == [49])
    }

    @Test("A newer request cancels the running one and waits for it: one at a time, the last one finishes")
    func cancelsStale() async throws {
        let request = PluginLatestRequest()
        let log = Log()
        for index in 0..<5 {
            // Each request starts before the next is scheduled; the others would run a minute unless cancelled.
            request.schedule(after: .zero, work(index, log, milliseconds: index == 4 ? 50 : 60_000))
            try await until { log.started.contains(index) }
        }
        try await settle(request)
        #expect(!log.overlapped)
        #expect(log.finished == [4])
        #expect(log.cancelled == [0, 1, 2, 3])
    }

    @Test("Cancel drops the waiting request and stops the running one")
    func cancel() async throws {
        let request = PluginLatestRequest()
        let log = Log()
        request.schedule(after: .zero, work(1, log, milliseconds: 60_000))
        try await until { log.started == [1] }
        request.schedule(after: .milliseconds(100), work(2, log))
        request.cancel()
        try await settle(request)
        try await until { !log.cancelled.isEmpty }
        #expect(log.cancelled == [1] && log.finished.isEmpty && log.started == [1])
    }
}
