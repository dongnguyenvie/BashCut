import AVFoundation
import BashCutProject
import Testing
@testable import BashCutEngine

struct SpeedRampPlanTests {
    @Test("Flat ramps use one piece and preserve exact endpoints")
    func flat() throws {
        let curve = try SpeedCurve([.init(t: 0, speed: 2), .init(t: 1, speed: 2)])
        let item = Item(id: "ramp", at: 17, duration: 900, sourceIn: 41)
        let plan = SpeedRampPlan(curve: curve, item: item, mediaFPS: FrameRate(), fps: FrameRate())
        #expect(plan.pieces.count == 1)
        let piece = try #require(plan.pieces.first)
        #expect(abs(piece.target.duration.seconds - 900 / FrameRate().value) < 0.00001)
        #expect(abs(piece.source.duration.seconds - 1_800 / FrameRate().value) < 0.00001)
    }

    @Test("Adaptive ramp pieces stay within a quarter source frame across presets and long clips")
    func accuracy() throws {
        for preset in SpeedCurve.presets {
            let curve = try #require(SpeedCurve.preset(preset.id))
            for duration in [7, 300, 108_000] {
                let item = Item(id: "ramp", at: 19, duration: duration, sourceIn: 11)
                let fps = FrameRate(), mediaFPS = FrameRate()
                let plan = SpeedRampPlan(curve: curve, item: item, mediaFPS: mediaFPS, fps: fps)
                for (index, piece) in plan.pieces.enumerated() {
                    if index > 0 {
                        #expect(plan.pieces[index - 1].source.end == piece.source.start)
                        #expect(plan.pieces[index - 1].target.end == piece.target.start)
                    }
                    let timeline = piece.target.start.seconds + piece.target.duration.seconds / 2
                    let fraction = (timeline - Double(item.at) / fps.value) / (Double(duration) / fps.value)
                    let expected = Double(item.sourceIn) / mediaFPS.value + curve.integral(to: fraction) * Double(duration) / fps.value
                    let actual = piece.source.start.seconds + piece.source.duration.seconds / 2
                    #expect(abs(actual - expected) * mediaFPS.value <= 0.251)
                }
                let end = try #require(plan.pieces.last)
                #expect(abs(end.target.end.seconds - Double(item.end) / fps.value) < 0.00001)
                #expect(abs(end.source.end.seconds - (Double(item.sourceIn) / mediaFPS.value
                    + curve.average * Double(duration) / fps.value)) < 0.00001)
            }
        }
    }

    @Test("Ramp plans survive look edits and invalidate on timing or curve edits")
    func cache() throws {
        var item = Item(id: "ramp", at: 0, duration: 30)
        item["speedCurve"] = try #require(SpeedCurve.preset("hero")).json
        var cache = SpeedRampPlans()
        _ = cache.plan(for: item, mediaFPS: FrameRate(), fps: FrameRate())
        item["opacity"] = .number(0.5)
        _ = cache.plan(for: item, mediaFPS: FrameRate(), fps: FrameRate())
        #expect(cache.builds == 1)
        item["at"] = .integer(20)
        _ = cache.plan(for: item, mediaFPS: FrameRate(), fps: FrameRate())
        #expect(cache.builds == 2)
        item["speedCurve"] = try #require(SpeedCurve.preset("bullet")).json
        _ = cache.plan(for: item, mediaFPS: FrameRate(), fps: FrameRate())
        #expect(cache.builds == 3)
        cache.retain([])
        _ = cache.plan(for: item, mediaFPS: FrameRate(), fps: FrameRate())
        #expect(cache.builds == 4)
    }
}
