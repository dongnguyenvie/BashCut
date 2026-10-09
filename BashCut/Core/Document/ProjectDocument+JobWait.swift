import BashCutAutomation
import BashCutProject
import Foundation

/// `jobs.wait` (P2-G4): one job until it moves on or ends, or several until all have ended.
extension ProjectDocument {
    /// `jobs.wait` (P2-G4): the job once its state or step changes, it finishes, or `seconds` pass.
    func waitForJob(_ id: String, seconds: Int) async throws -> JSONValue {
        guard jobs.job(id) != nil else { throw RPCFailure(-32602, "Unknown job") }
        guard let (job, changed) = try await jobs.wait(id, for: .seconds(seconds)) else {
            throw RPCFailure(-32602, "The job is gone: the project was closed or switched")
        }
        return .object(["job": job.json, "changed": .bool(changed), "timedOut": .bool(job.isActive && !changed)])
    }

    /// `jobs.wait --done` with one job: the job once it finished, or `seconds` passed; `{job, changed, timedOut}`.
    func waitForJobDone(_ id: String, seconds: Int) async throws -> JSONValue {
        guard let start = jobs.job(id) else { throw RPCFailure(-32602, "Unknown job") }
        let result = try await waitForJobs([id], seconds: seconds).object
        let job = jobs.job(id) ?? start
        return .object([
            "job": job.json, "changed": .bool(job.state != start.state || job.detail != start.detail),
            "timedOut": result["timedOut"] ?? .bool(job.isActive),
        ])
    }

    /// `jobs.wait` with several jobs: until every one has finished, or `seconds` passed; `{jobs, finished, timedOut}`.
    func waitForJobs(_ ids: [String], seconds: Int) async throws -> JSONValue {
        for id in ids where jobs.job(id) == nil { throw RPCFailure(-32602, "Unknown job \(id)") }
        let deadline = ContinuousClock.now + .seconds(seconds)
        while let active = ids.first(where: { jobs.job($0)?.isActive == true }), ContinuousClock.now < deadline {
            let left = ContinuousClock.now.duration(to: deadline)
            guard try await jobs.wait(active, for: left) != nil else {
                throw RPCFailure(-32602, "The job is gone: the project was closed or switched")
            }
        }
        let list = ids.compactMap { jobs.job($0) }
        return .object([
            "jobs": .array(list.map(\.json)), "finished": .integer(list.filter { !$0.isActive }.count),
            "timedOut": .bool(list.contains { $0.isActive }),
        ])
    }
}
