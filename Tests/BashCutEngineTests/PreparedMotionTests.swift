import BashCutProject
import CoreGraphics
import Foundation
import Testing
@testable import BashCutEngine

struct PreparedMotionTests {
    @Test("Prepared interpolation preserves all easing modes, shifted keys and random-access boundaries",
           arguments: ItemMotion.Ease.allCases)
    func interpolation(ease: ItemMotion.Ease) {
        let keys: [ItemMotion.Key] = [
            .init(frame: -40, value: 1, ease: ease), .init(frame: 10, value: 8, ease: ease),
            .init(frame: 55, value: -3, ease: ease), .init(frame: 120, value: 2, ease: ease)
        ]
        let original = ItemMotion(keys: ["pan": keys]), prepared = PreparedKeyframes(keys, fallback: 100)
        let frames = [-100.0, -40, -39.999, 0, 9.999, 10, 10.001, 30, 54.999, 55, 119.999, 120, 500]
        for frame in frames + frames.reversed() {
            let expected = original.value("pan", at: frame) ?? 100
            #expect(abs(prepared.value(at: frame) - expected) < 1e-12)
        }
        #expect(PreparedKeyframes([], fallback: 4).value(at: 123) == 4)
        #expect(PreparedKeyframes([keys[0]], fallback: 4).value(at: 123) == 1)
    }

    @Test("Prepared picture samples preserve static defaults, fractional FPS and transition holds")
    func picture() {
        var item = Item(id: "motion", at: 31, duration: 83)
        item["transform"] = .object(["zoom": .number(1.2), "pan": .number(12), "tilt": .number(-7)])
        item["opacity"] = .number(0.7)
        let original = ItemMotion(keys: ["rotation": [.init(frame: 0, value: -10), .init(frame: 60, value: 22)]])
        let layer = LayerMotion(motion: original, item: item, fps: 30000 / 1001)
        let placement = placement()
        for time in [-1.0, 0, 1.2, 2, 3, 4, 10] {
            let actual = layer.sample(at: time)
            let rotation = original.value("rotation", at: layer.frame(at: time)) ?? 0
            #expect(actual.zoom == 1.2 && actual.pan == 12 && actual.tilt == -7 && actual.opacity == 0.7)
            #expect(abs(actual.rotation - rotation) < 1e-12)
            let expected = placement.transform(zoom: 1.2, pan: 12, tilt: -7, rotation: rotation)
            let transform = actual.transform(placement)
            for (left, right) in zip(components(transform), components(expected)) {
                #expect(abs(left - right) < 1e-10)
            }
        }
    }

    @Test("Prepared motion benchmark checks identical transform and opacity checksums", arguments: [2, 1000])
    func benchmark(keyCount: Int) {
        let keys = (0..<keyCount).map { index in
            ItemMotion.Key(frame: index * 5, value: 1 + Double(index % 7) / 10,
                           ease: ItemMotion.Ease.allCases[index % ItemMotion.Ease.allCases.count])
        }
        let original = ItemMotion(keys: Dictionary(uniqueKeysWithValues: ItemMotion.pictureProperties.map { ($0, keys) }))
        let item = Item(id: "bench", at: 30, duration: keyCount * 5)
        let layer = LayerMotion(motion: original, item: item, fps: 30), placement = placement()
        var oldSum = 0.0, newSum = 0.0
        let count = 10_000
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<count {
            let seconds = Double((index * 137) % (keyCount * 5 + 60)) / 30 + 0.003
            func value(_ property: String) -> Double {
                original.value(property, at: layer.frame(at: seconds)) ?? layer.base[property] ?? 0
            }
            let transform = placement.transform(zoom: value("zoom"), pan: value("pan"),
                                                tilt: value("tilt"), rotation: value("rotation"))
            oldSum += transform.a + transform.tx + value("opacity")
        }
        let middle = CFAbsoluteTimeGetCurrent()
        for index in 0..<count {
            let seconds = Double((index * 137) % (keyCount * 5 + 60)) / 30 + 0.003
            let sample = layer.sample(at: seconds), transform = sample.transform(placement)
            newSum += transform.a + transform.tx + sample.opacity
        }
        let end = CFAbsoluteTimeGetCurrent()
        #expect(abs(oldSum - newSum) < 1e-7)
        print("PREPARED_MOTION keys=\(keyCount) frames=\(count) old_ms=\((middle - start) * 1000) new_ms=\((end - middle) * 1000)")
    }

    private func placement() -> ClipPlacement {
        ClipPlacement(orientation: .identity, size: CGSize(width: 1920, height: 1080), baseScale: 0.5,
                      canvas: CGSize(width: 540, height: 960))
    }

    private func components(_ value: CGAffineTransform) -> [CGFloat] {
        [value.a, value.b, value.c, value.d, value.tx, value.ty]
    }
}
