import AVFoundation

/// One exact seek in flight per player. New requests replace the pending target instead of queuing decodes.
@MainActor
final class PreviewSeekQueue {
    typealias Seek = @MainActor (CMTime, @escaping @Sendable (Bool) -> Void) -> Void
    private var pending: (time: CMTime, seek: Seek)?
    private var inFlight = false
    private var generation = 0
    private(set) var count = 0

    func submit(_ time: CMTime, seek: @escaping Seek) {
        pending = (time, seek)
        drain()
    }

    func reset() {
        generation += 1
        pending = nil
        inFlight = false
    }

    private func drain() {
        guard !inFlight, let pending else { return }
        self.pending = nil
        inFlight = true
        count += 1
        let generation = generation
        pending.seek(pending.time) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.inFlight = false
                self.drain()
            }
        }
    }
}
