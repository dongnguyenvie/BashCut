import Foundation
import Testing
@testable import BashCutEngine

private enum TransferTestError: Error { case read, writer }

private final class TransferState: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?
    private var values: [Double] = []
    var failure: (any Error)? { lock.withLock { error } }
    var progress: [Double] { lock.withLock { values } }
    func fail() { lock.withLock { error = TransferTestError.writer } }
    func report(_ value: Double) { lock.withLock { values.append(value) } }
}

private final class TestStream: @unchecked Sendable {
    private let lock = NSLock()
    private let key = DispatchSpecificKey<Bool>()
    private var queue: DispatchQueue?
    private var callback: (@Sendable () -> Void)?
    private var ready = true
    private var reads = 0
    private var finishes = 0
    private let samples: Int
    var gate: DispatchSemaphore?
    var throwOnRead = false
    var readCount: Int { lock.withLock { reads } }
    var finishCount: Int { lock.withLock { finishes } }

    init(samples: Int, ready: Bool = true) { self.samples = samples; self.ready = ready }

    func setReady(_ value: Bool) {
        let registered = lock.withLock {
            ready = value
            return (queue, callback)
        }
        if value, let queue = registered.0, let callback = registered.1 { queue.async(execute: callback) }
    }

    var lane: ExportSampleTransfer.Lane {
        ExportSampleTransfer.Lane(request: { queue, callback in
            self.lock.withLock { self.queue = queue; self.callback = callback }
            queue.setSpecific(key: self.key, value: true)
            queue.async(execute: callback)
        }, ready: { self.lock.withLock { self.ready } }, next: {
            #expect(DispatchQueue.getSpecific(key: self.key) == true)
            let index = self.lock.withLock { self.reads += 1; return self.reads - 1 }
            self.gate?.wait()
            if self.throwOnRead { throw TransferTestError.read }
            return index < self.samples ? Double(index) : nil
        }, finish: {
            #expect(DispatchQueue.getSpecific(key: self.key) == true)
            self.lock.withLock { self.finishes += 1 }
        })
    }
}

struct ExportSampleTransferTests {
    @Test("Streams drain independently under backpressure and finish exactly once")
    func backpressure() async throws {
        let video = TestStream(samples: 20, ready: false), audio = TestStream(samples: 50), state = TransferState()
        let transfer = ExportSampleTransfer(lanes: [video.lane, audio.lane], duration: 20,
                                      progress: { state.report($0) }, failure: { state.failure }, interrupt: {})
        let task = Task { try await transfer.run() }
        defer { task.cancel() }
        try await wait { audio.finishCount == 1 }
        #expect(video.readCount == 0 && video.finishCount == 0)
        video.setReady(true)
        try await task.value
        #expect(video.readCount == 21 && audio.readCount == 51)
        #expect(video.finishCount == 1 && audio.finishCount == 1)
        #expect(state.progress == state.progress.sorted())
        #expect(state.progress.last == 0.95)
        video.setReady(true) // A stale callback after completion must not read or finish again.
        try await Task.sleep(for: .milliseconds(10))
        #expect(video.readCount == 21 && video.finishCount == 1)
    }

    @Test("Failure while all inputs are not ready still completes without a readiness callback")
    func idleFailure() async throws {
        let video = TestStream(samples: 20, ready: false), state = TransferState()
        let transfer = ExportSampleTransfer(lanes: [video.lane], duration: 20,
                                      progress: { _ in }, failure: { state.failure }, interrupt: {})
        let task = Task { try await transfer.run() }
        state.fail()
        await #expect(throws: TransferTestError.self) { try await task.value }
        #expect(video.readCount == 0 && video.finishCount == 1)
    }

    @Test("Cancellation interrupts a blocked read and drains it before returning")
    func blockedCancellation() async throws {
        let stream = TestStream(samples: 20), gate = DispatchSemaphore(value: 0)
        stream.gate = gate
        let transfer = ExportSampleTransfer(lanes: [stream.lane], duration: 20,
                                      progress: { _ in }, failure: { nil }, interrupt: { gate.signal() })
        let task = Task { try await transfer.run() }
        defer { task.cancel() }
        try await wait { stream.readCount == 1 }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(stream.readCount == 1 && stream.finishCount == 1)
    }

    @Test("A read that returns on its own is never interrupted, so the reader is not cancelled under it")
    func gracefulCancellation() async throws {
        let stream = TestStream(samples: 20), gate = DispatchSemaphore(value: 0), state = TransferState()
        stream.gate = gate
        let transfer = ExportSampleTransfer(lanes: [stream.lane], duration: 20, progress: { _ in }, failure: { nil },
                                            interrupt: { state.fail(); gate.signal() }, interruptGrace: .seconds(5))
        let task = Task { try await transfer.run() }
        defer { task.cancel() }
        try await wait { stream.readCount == 1 }
        task.cancel()
        try await Task.sleep(for: .milliseconds(50))
        gate.signal() // The in-flight decode finishes normally within the grace period.
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(state.failure == nil)
        #expect(stream.readCount == 1 && stream.finishCount == 1)
    }

    @Test("Read errors interrupt other lanes and preserve the original error")
    func readFailure() async {
        let bad = TestStream(samples: 20), waiting = TestStream(samples: 20, ready: false)
        bad.throwOnRead = true
        let transfer = ExportSampleTransfer(lanes: [bad.lane, waiting.lane], duration: 20,
                                      progress: { _ in }, failure: { nil }, interrupt: {})
        await #expect(throws: TransferTestError.self) { try await transfer.run() }
        #expect(bad.finishCount == 1 && waiting.finishCount == 1)
    }

    @Test("Cancellation before registration resumes once without reading")
    func cancelledBeforeStart() async {
        let stream = TestStream(samples: 20)
        let transfer = ExportSampleTransfer(lanes: [stream.lane], duration: 20,
                                      progress: { _ in }, failure: { nil }, interrupt: {})
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await transfer.run()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(stream.readCount == 0)
    }

    private func wait(_ condition: @escaping @Sendable () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}
