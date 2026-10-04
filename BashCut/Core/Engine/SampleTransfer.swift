import Foundation

/// Pulls each stream on its own serial queue. No blocking media reads run on Swift's cooperative executor.
/// The control queue owns completion; lane queues own EOF/finish state; the stop flag is lock-protected.
final class SampleTransfer: @unchecked Sendable {
    struct Lane: Sendable {
        let request: @Sendable (DispatchQueue, @escaping @Sendable () -> Void) -> Void
        let ready: @Sendable () -> Bool
        /// Appends one sample and returns its timestamp; nil means EOF.
        let next: @Sendable () throws -> Double?
        let finish: @Sendable () -> Void
    }

    private final class Stream: @unchecked Sendable {
        let lane: Lane
        let queue: DispatchQueue
        var finished = false // Accessed only on queue.
        init(_ lane: Lane, index: Int) {
            self.lane = lane
            queue = DispatchQueue(label: "app.bashcut.export.stream.\(index)")
        }
        func finish() {
            guard !finished else { return }
            finished = true
            lane.finish()
        }
    }

    private enum Phase { case idle, running, stopping, finished }
    private let control = DispatchQueue(label: "app.bashcut.export.transfer")
    private let lock = NSLock()
    private var stopRequested = false
    private var shouldStop: Bool { lock.withLock { stopRequested } }
    private let streams: [Stream]
    private let duration: Double
    private let progress: @Sendable (Double) -> Void
    private let failure: @Sendable () -> (any Error)?
    private let interrupt: @Sendable () -> Void
    // Control-queue state, except lastProgress which belongs to stream zero's queue.
    private var phase = Phase.idle
    private var error: (any Error)?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var completed = 0
    private var lastProgress = -1.0
    private var monitor: DispatchSourceTimer?

    init(lanes: [Lane], duration: Double, progress: @escaping @Sendable (Double) -> Void,
         failure: @escaping @Sendable () -> (any Error)?, interrupt: @escaping @Sendable () -> Void) {
        streams = lanes.enumerated().map { Stream($0.element, index: $0.offset) }
        self.duration = duration
        self.progress = progress
        self.failure = failure
        self.interrupt = interrupt
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                control.async { self.start(continuation) }
            }
        } onCancel: {
            self.requestStop(CancellationError())
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
        if phase == .stopping { complete(); return }
        phase = .running
        guard !streams.isEmpty else { complete(); return }
        // Readiness callbacks need not fire after an asynchronous writer failure. This low-frequency
        // health check handles that terminal case; sample transfer itself is entirely readiness-driven.
        let timer = DispatchSource.makeTimerSource(queue: control)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.phase == .running, let error = self.failure() else { return }
            self.stop(error)
        }
        monitor = timer
        timer.resume()
        for (index, stream) in streams.enumerated() {
            stream.lane.request(stream.queue) { [weak self] in self?.drain(index) }
        }
    }

    private func drain(_ index: Int) {
        let stream = streams[index]
        guard !stream.finished else { return }
        do {
            while !shouldStop && stream.lane.ready() {
                let time = try autoreleasepool { try stream.lane.next() }
                guard let time else {
                    stream.finish()
                    control.async { self.reachedEnd() }
                    return
                }
                if index == 0, duration > 0, time.isFinite {
                    let value = min(0.99, max(0, time / duration))
                    if value - lastProgress >= 0.005 {
                        lastProgress = value
                        progress(value)
                    }
                }
            }
        } catch {
            requestStop(error)
        }
    }

    private func reachedEnd() {
        guard phase == .running else { return }
        completed += 1
        guard completed == streams.count else { return }
        if let error = failure() { stop(error) } else { complete() }
    }

    private func requestStop(_ error: any Error) {
        lock.withLock { stopRequested = true }
        control.async { self.stop(error) }
    }

    private func stop(_ error: any Error) {
        guard phase != .finished, phase != .stopping else { return }
        self.error = error
        lock.withLock { stopRequested = true }
        monitor?.cancel()
        let wasIdle = phase == .idle
        phase = .stopping
        interrupt() // Cancels native reading to unblock an in-flight copyNextSampleBuffer.
        guard !wasIdle else { return } // start() will install and resume the continuation.
        let drained = DispatchGroup()
        for stream in streams {
            drained.enter()
            stream.queue.async {
                stream.finish()
                drained.leave()
            }
        }
        // Writer cancellation/cleanup by the caller cannot race any remaining sample append.
        drained.notify(queue: control) { self.complete() }
    }

    private func complete() {
        guard phase != .finished else { return }
        phase = .finished
        monitor?.cancel()
        monitor = nil
        let continuation = continuation
        self.continuation = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
