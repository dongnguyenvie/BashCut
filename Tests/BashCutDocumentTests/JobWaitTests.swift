import BashCutDocument
import BashCutPlugins
import BashCutProject
import Foundation
import Testing

/// `jobs.wait`, usage and request IDs on jobs (P2-G4).
@MainActor
struct JobWaitTests {
    /// Work that waits until the test opens `gate`.
    private final class Gate {
        var open = false
        func wait() async throws { while !open { try await Task.sleep(for: .milliseconds(5)) } }
    }

    @Test("A wait returns when the step changes or the job finishes, and times out on progress alone")
    func wait() async throws {
        let center = JobCenter()
        let gate = Gate(), stepped = Gate()
        let id = center.start("voice.speak", author: .claude, work: { reporter in
            reporter.progress(0.2)
            try await stepped.wait()
            reporter.detail("take 2 of 3")
            try await gate.wait()
            return .bool(true)
        })
        try await Task.sleep(for: .milliseconds(30))
        let idle = try #require(try await center.wait(id, for: .milliseconds(150), interval: .milliseconds(10)))
        #expect(!idle.changed && idle.job.state == .running && idle.job.progress == 0.2)

        stepped.open = true
        let step = try #require(try await center.wait(id, for: .seconds(5), interval: .milliseconds(10)))
        #expect(step.changed && step.job.detail == "take 2 of 3" && step.job.json.object["step"] == .string("take 2 of 3"))

        gate.open = true
        let done = try #require(try await center.wait(id, for: .seconds(5), interval: .milliseconds(10)))
        #expect(done.changed && done.job.state == .completed)
        // A finished job answers at once.
        let start = ContinuousClock.now
        let again = try #require(try await center.wait(id, for: .seconds(5)))
        #expect(!again.changed && ContinuousClock.now - start < .milliseconds(50))
        #expect(try await center.wait("missing", for: .seconds(1)) == nil)
    }

    @Test("Plugin calls inside a job report to its usage and carry its request ID; wallSec counts the run")
    func usage() async throws {
        let center = JobCenter()
        let id = center.start("library.generate", author: .codex, requestID: "music-1", work: { _ in
            let context = PluginCallContext.current
            context.usage?.record(provider: "music/gen", usage: .object([
                "units": .object(["seconds": .integer(30)]), "costUSD": .number(0.12),
            ]))
            return .string(context.requestID ?? "none")
        })
        let done = try #require(try await center.wait(id, for: .seconds(5), interval: .milliseconds(5)))
        let json = done.job.json.object
        #expect(json["result"] == .string("music-1") && json["requestId"] == .string("music-1"))
        let usage = json["usage"]?.object ?? [:]
        #expect(usage["provider"] == .string("music/gen") && usage["costUSD"] == .number(0.12))
        #expect(usage["costSource"] == .string("provider") && usage["units"] == .object(["seconds": .number(30)]))
        #expect((usage["wallSec"]?.double ?? -1) >= 0)
        #expect(center.job(method: "library.generate", requestID: "music-1")?.id == id)
        #expect(center.job(method: "voice.speak", requestID: "music-1") == nil)
        // Outside a job there is no usage to report to.
        #expect(PluginCallContext.current.usage == nil)
    }

    @Test("A queued job has no wall time and no usage yet")
    func queued() {
        let center = JobCenter()
        let id = center.enqueue("export.start", author: .user)
        let usage = center.job(id)?.json.object["usage"]?.object ?? [:]
        #expect(usage["wallSec"] == .null && usage["provider"] == .null && usage["costUSD"] == .null)
    }
}
