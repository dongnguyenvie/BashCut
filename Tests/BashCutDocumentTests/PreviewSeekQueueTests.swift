import AVFoundation
@testable import BashCutDocument
import Testing

@MainActor
struct PreviewSeekQueueTests {
    @Test("Each player chases only the newest pending target")
    func coalesces() async {
        let program = PreviewSeekQueue(), comparison = PreviewSeekQueue()
        var programFrames: [Int64] = [], comparisonFrames: [Int64] = []
        var programDone: (@Sendable (Bool) -> Void)?
        var comparisonDone: (@Sendable (Bool) -> Void)?
        for frame in 0..<100 {
            let time = CMTime(value: Int64(frame), timescale: 30)
            program.submit(time) { time, done in programFrames.append(time.value); programDone = done }
            comparison.submit(time) { time, done in comparisonFrames.append(time.value); comparisonDone = done }
        }
        #expect(programFrames == [0])
        #expect(comparisonFrames == [0])
        programDone?(true)
        for _ in 0..<100 where programFrames.count < 2 { await Task.yield() }
        #expect(programFrames == [0, 99])
        #expect(comparisonFrames == [0])
        comparisonDone?(true)
        for _ in 0..<100 where comparisonFrames.count < 2 { await Task.yield() }
        #expect(comparisonFrames == [0, 99])
        #expect(program.count == 2 && comparison.count == 2)
    }

    @Test("A stale player completion cannot release the replacement player's pending seek")
    func reset() async {
        let queue = PreviewSeekQueue()
        var oldDone: (@Sendable (Bool) -> Void)?
        var newDone: (@Sendable (Bool) -> Void)?
        var frames: [Int64] = []
        queue.submit(.zero) { _, done in oldDone = done }
        queue.reset()
        queue.submit(CMTime(value: 1, timescale: 30)) { time, done in frames.append(time.value); newDone = done }
        queue.submit(CMTime(value: 2, timescale: 30)) { time, _ in frames.append(time.value) }
        oldDone?(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(frames == [1])
        newDone?(false)
        for _ in 0..<100 where frames.count < 2 { await Task.yield() }
        #expect(frames == [1, 2])
    }
}
