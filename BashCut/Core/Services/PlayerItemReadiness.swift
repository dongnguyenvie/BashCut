import AVFoundation
import BashCutProject
import Foundation

/// Owns one readiness observation and resumes its waiter exactly once on readiness, failure or cancellation.
@MainActor
final class PlayerItemReadiness {
    struct Timeout: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var observation: NSKeyValueObservation?
    private var timer: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?

    static func wait(_ item: AVPlayerItem, message: String, timeout: Duration = .seconds(30)) async throws {
        let waiter = PlayerItemReadiness()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                waiter.observation = item.observe(\.status, options: [.initial, .new]) { [weak waiter] item, _ in
                    Task { @MainActor in waiter?.check(item, message: message) }
                }
                waiter.timer = Task { [weak waiter] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    waiter?.finish(.failure(Timeout(message: message)))
                }
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
    }

    private func check(_ item: AVPlayerItem, message: String) {
        switch item.status {
        case .readyToPlay: finish(.success(()))
        case .failed: finish(.failure(item.error ?? ProjectError.invalid(message)))
        default: break
        }
    }

    private func finish(_ result: Result<Void, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        observation?.invalidate()
        observation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(with: result)
    }
}
