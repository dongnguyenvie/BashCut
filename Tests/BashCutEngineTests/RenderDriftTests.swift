import BashCutProject
import Foundation
import Testing

@testable import BashCutEngine

/// Timing of a render against the timeline's sound (P0-B2 `review.sync --rendered`), on synthetic envelopes.
struct RenderDriftTests {
    /// A level that changes at random (repeatably) at 100 windows a second.
    func envelope(seconds: Int) -> [Float] {
        var state: UInt64 = 42
        return (0..<(seconds * 100)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return -60 + Float(state >> 40) / Float(1 << 24) * 40
        }
    }

    @Test("A render that is late by a growing amount reports each window's lag and the drift")
    func drift() {
        let reference = envelope(seconds: 40)
        // 0 ms late at the start, 30 ms more every 10 s.
        var rendered: [Float] = []
        for window in 0..<4 {
            let lag = window * 3
            rendered += (0..<1_000).map { reference[max(0, window * 1_000 + $0 - lag)] }
        }
        rendered += [Float](repeating: -60, count: 100)
        let windows = RenderDrift.windows(reference: reference, rendered: rendered)
        #expect(windows.map(\.lagMs) == [0, 30, 60, 90])
        #expect(windows.allSatisfy { $0.correlation > 0.9 })
        let json = RenderDrift.json(windows, renderedSeconds: 41, timelineSeconds: 40).object
        #expect(json["driftMsPerMinute"] == .number(180))
        #expect(json["lagStartMs"] == .number(0) && json["lagEndMs"] == .number(90))
    }

    @Test("Silent stretches are skipped")
    func silence() {
        let flat = [Float](repeating: -90, count: 2_000)
        #expect(RenderDrift.windows(reference: flat, rendered: flat).isEmpty)
    }
}
