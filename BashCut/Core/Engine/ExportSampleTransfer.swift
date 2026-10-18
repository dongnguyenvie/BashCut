import Foundation

/// Pulls each stream on its own serial queue. No blocking media reads run on Swift's cooperative executor.
/// The control queue owns completion; lane queues own EOF/finish state; the stop flag is lock-protected.
///
/// A read is never interrupted: cancelling the reader while a lane waits inside `copyNextSampleBuffer` frees the wait
/// condition under it and crashes the app (`pthread_mutex_lock` at 0x0 on `export.stream`). A stop that a blocked read
/// outlives returns at once and leaves the read to finish on its own; `release` cancels the reader and writer only
/// once every lane has left its read.
final class ExportSampleTransfer: @unchecked Sendable {
    struct Lane: Sendable {
        let request: @Sendable (DispatchQueue, @escaping @Sendable () -> Void) -> Void
        let ready: @Sendable () -> Bool
        /// Appends one sample and returns its timestamp; nil means EOF.
        let next: @Sendable () throws -> Double?
        let finish: @Sendable () -> Void
        /// Named in the stall report (video, audio).
        var name = "stream"
    }

    private final class Stream: @unchecked Sendable {
        let lane: Lane
        let queue: DispatchQueue
        var finished = false // Accessed only on queue.
        // Transfer-lock-protected: the lane's latest sample time and whether it is inside a read.
        var lastTime = -1.0
        var reading = false
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
    private let release: @Sendable () -> Void
    private let abandonAfter: DispatchTimeInterval
    private let stallLimit: TimeInterval
    // Lock-protected: when any lane last appended a sample, and the latest timeline time written.
    private var lastSample = DispatchTime.now()
    private var lastTime = 0.0
    // Control-queue state, except lastProgress which belongs to stream zero's queue.
    private var phase = Phase.idle
    private var error: (any Error)?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var completed = 0
    private var lastProgress = -1.0
    private var monitor: DispatchSourceTimer?

    init(lanes: [Lane], duration: Double, progress: @escaping @Sendable (Double) -> Void,
         failure: @escaping @Sendable () -> (any Error)?, release: @escaping @Sendable () -> Void,
         abandonAfter: DispatchTimeInterval = .seconds(2), stallLimit: TimeInterval = 60) {
        streams = lanes.enumerated().map { Stream($0.element, index: $0.offset) }
        self.duration = duration
        self.progress = progress
        self.failure = failure
        self.release = release
        self.abandonAfter = abandonAfter
        self.stallLimit = stallLimit
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
        lock.withLock { lastSample = .now() }
        timer.setEventHandler { [weak self] in
            guard let self, self.phase == .running else { return }
            if let error = self.failure() { self.stop(error); return }
            let (since, time) = self.lock.withLock { (self.lastSample, self.lastTime) }
            let idle = Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1e9
            if idle > self.stallLimit {
                self.stop(ExportStallError(timelineSeconds: time, idleSeconds: self.stallLimit, lanes: self.laneReport()))
            }
        }
        monitor = timer
        timer.resume()
        for (index, stream) in streams.enumerated() {
            stream.lane.request(stream.queue) { [weak self] in self?.drain(index) }
        }
    }

    /// Where each lane stands when the transfer stalls: blocked inside a read, or waiting for the writer to want more.
    private func laneReport() -> String {
        streams.map { stream in
            let (time, reading) = lock.withLock { (stream.lastTime, stream.reading) }
            let state = reading ? "blocked in read" : (stream.lane.ready() ? "idle" : "waiting for writer")
            return "\(stream.lane.name) at \(String(format: "%.2f", time)) s \(state)"
        }.joined(separator: "; ")
    }

    private func drain(_ index: Int) {
        let stream = streams[index]
        guard !stream.finished else { return }
        do {
            while !shouldStop && stream.lane.ready() {
                lock.withLock { stream.reading = true }
                let time = try autoreleasepool { try stream.lane.next() }
                lock.withLock {
                    stream.reading = false
                    lastSample = .now()
                    if let time, time.isFinite {
                        lastTime = max(lastTime, time)
                        stream.lastTime = time
                    }
                }
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
        guard !wasIdle else { release(); return } // No read is in flight; start() will resume the continuation.
        // Lanes stop after their current sample. A read still blocked after the grace period (a stalled decode)
        // is abandoned rather than interrupted: the job ends now, and the reader is released when the read returns.
        let abandon = DispatchWorkItem { [weak self] in self?.complete() }
        control.asyncAfter(deadline: .now() + abandonAfter, execute: abandon)
        let drained = DispatchGroup()
        for stream in streams {
            drained.enter()
            stream.queue.async {
                stream.finish()
                drained.leave()
            }
        }
        // Reader and writer cancellation cannot race any remaining read or sample append.
        drained.notify(queue: control) {
            abandon.cancel()
            self.release()
            self.complete()
        }
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

/// No lane wrote a sample for `idleSeconds`: a decode or the compositor stopped answering.
struct ExportStallError: LocalizedError, Equatable {
    let timelineSeconds: Double
    let idleSeconds: Double
    /// Each lane's latest sample and state (blocked in a read, waiting for the writer); empty when unknown.
    var lanes = ""

    var errorDescription: String? {
        String(format: "Rendering stopped answering near %.2f s of the timeline: no frame or sound for %.0f s. "
            + "A clip there may be unreadable at its speed; check it with ui frame, or replace it.", timelineSeconds, idleSeconds)
            + (lanes.isEmpty ? "" : " (\(lanes))")
    }
}
