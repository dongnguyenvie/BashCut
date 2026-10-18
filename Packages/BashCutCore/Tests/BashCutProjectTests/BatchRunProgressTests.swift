import BashCutProject
import Foundation
import Testing

struct BatchRunProgressTests {
    private func run(items count: Int) -> BatchRunStatus {
        let pipeline = BatchPipeline(inputs: [BatchInput(path: "/tmp")], steps: [BatchStep("a"), BatchStep("b")])
        let items = (0..<count).map { BatchItemSource(name: "\($0)", url: URL(fileURLWithPath: "/tmp/\($0).mp4"), kind: .file) }
        return BatchRunStatus(id: "batch-test", pipeline: pipeline, items: items, state: .running)
    }

    @Test("The estimate is the completed items' average times the items left, plus what is left of the running one")
    func estimate() {
        let start = Date(timeIntervalSince1970: 1_000)
        var run = run(items: 5)
        run.runningSince = start
        #expect(run.remaining(now: start + 10) == nil, "nothing finished yet")
        for (index, seconds) in [(0, 60.0), (1, 120.0)] {
            run.items[index].state = .completed
            run.items[index].startedAt = start + (index == 0 ? 0 : 60)
            run.items[index].finishedAt = run.items[index].startedAt! + seconds
        }
        run.items[2].state = .running
        run.items[2].startedAt = start + 180
        // Average 90 s; two waiting; the running one is 30 s in.
        let remaining: Double = run.remaining(now: start + 210) ?? 0
        #expect(abs(remaining - 240) < 0.001)
        #expect(run.elapsed(now: start + 210) == 210)
        #expect(run.fractionDone == 0.4)
        run.state = .completed
        #expect(run.remaining(now: start + 210) == nil)
    }

    @Test("Retry keeps completed steps; an interrupted run marks what was running and keeps the rest waiting")
    func retryAndInterrupt() throws {
        var run = run(items: 3)
        run.items[0].state = .completed
        run.items[0].steps = run.items[0].steps.map { var step = $0; step.state = .completed; return step }
        run.items[1].state = .running
        run.items[1].steps[0].state = .completed
        run.items[1].steps[1].state = .running
        #expect(run.retryableItems.isEmpty, "a running run cannot be retried")
        run.markInterrupted()
        #expect(run.state == .interrupted)
        #expect(run.items.map(\.state) == [.completed, .interrupted, .waiting])
        #expect(run.items[1].steps.map(\.state) == [.waiting, .waiting], "its unsaved steps run again")
        #expect(run.retryableItems == [1, 2])

        let data = try JSONEncoder().encode(run)
        #expect(try JSONDecoder().decode(BatchRunStatus.self, from: data) == run)

        let retried = run.prepareRetry([1])
        #expect(retried)
        #expect(run.state == .waiting)
        #expect(run.items.map(\.state) == [.completed, .waiting, .waiting])
        #expect(run.items[1].steps.map(\.state) == [.waiting, .waiting])
        let completed = run.prepareRetry([0])
        #expect(!completed, "a completed item is not retried")
    }
}
