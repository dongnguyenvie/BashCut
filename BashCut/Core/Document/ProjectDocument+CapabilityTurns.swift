import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// The job a capability call runs as: what it calls and who asked.
struct CapabilityTurn {
    let capability: String
    let method: String
    let author: Author
    var detail: String?
    let requestID: String?
}

/// Capability jobs run one at a time per capability (#507).
extension ProjectDocument {
    /// Starts a job that calls `capability`, one at a time: a second request queues behind the first instead of
    /// failing busy, so the agent waits on both job IDs rather than polling and retrying. `queued` when it waits.
    func startCapabilityTurn(
        _ request: CapabilityTurn, work: @escaping @MainActor (JobReporter) async throws -> JSONValue,
        finished: @escaping @MainActor (Result<JSONValue, any Error>) -> Void
    ) -> (id: String, queued: Bool) {
        let capability = request.capability
        let previous = capabilityTurns[capability]
        let id = jobs.enqueue(request.method, author: request.author, detail: request.detail, requestID: request.requestID)
        let turn = Task { @MainActor [weak self] in
            await previous?.value
            while self?.plugins.calling.contains(capability) == true { try? await Task.sleep(for: .milliseconds(200)) }
            guard self?.jobs.job(id)?.state == .queued else { return }
            self?.jobs.run(id, work: work, finished: finished)
            while self?.jobs.job(id)?.isActive == true { try? await Task.sleep(for: .milliseconds(200)) }
        }
        capabilityTurns[capability] = turn
        Task { @MainActor [weak self] in
            await turn.value
            if self?.capabilityTurns[capability] == turn { self?.capabilityTurns[capability] = nil }
        }
        return (id, previous != nil || plugins.calling.contains(capability))
    }
}
