import BashCutProjectFixtures
import Testing

@testable import BashCutProject

struct SpeedCurveTests {
    private func item(_ project: Project, _ id: String) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    private func curve(_ points: [(Double, Double)]) throws -> SpeedCurve {
        try SpeedCurve(points.map { SpeedCurve.Point(t: $0.0, speed: $0.1) })
    }

    @Test("Integral, average, cuts and extensions follow the linear ramp")
    func math() throws {
        let ramp = try curve([(0, 1), (1, 3)])
        #expect(abs(ramp.average - 2) < 1e-12)
        #expect(abs(ramp.integral(to: 0.5) - 0.75) < 1e-12)
        #expect(abs(ramp.speed(at: 0.25) - 1.5) < 1e-12)
        let firstHalf = ramp.cut(from: 0, to: 0.5)
        #expect(firstHalf.points.map(\.speed) == [1, 2] && abs(firstHalf.average - 1.5) < 1e-12)
        let longer = ramp.extended(before: 0, after: 1)
        #expect(longer.points.map(\.t) == [0, 0.5, 1] && longer.points.last?.speed == 3)
        #expect(abs(longer.average - 2.5) < 1e-12)
        #expect(throws: ProjectError.self) { try curve([(0, 1)]) }
        #expect(throws: ProjectError.self) { try curve([(0, 1), (0.5, 40), (1, 1)]) }
        #expect(throws: ProjectError.self) { try curve([(0.1, 1), (1, 1)]) }
        #expect(SpeedCurve.presets.allSatisfy { SpeedCurve.preset($0.id) != nil })
    }

    @Test("A ramp keeps the source and sets the length from its average speed; linked sound follows")
    func apply() throws {
        let project = try ProjectFixtures.twoClips()
        let ramp = try curve([(0, 1), (0.5, 3), (1, 1)])
        let ramped = try project.applying(.setSpeedCurve(item: "left", curve: ramp, keepDuration: false)).project
        #expect(try item(ramped, "left").duration == 30)
        #expect(try item(ramped, "left").speed == 2)
        #expect(try item(ramped, "left").speedCurve == ramp)
        #expect(try item(ramped, "right").at == 30)
        // A constant speed replaces the ramp.
        let constant = try ramped.applying(.setSpeed(item: "left", speed: 1, keepDuration: false)).project
        #expect(try item(constant, "left").speedCurve == nil)
        // Removing the ramp keeps the clip at its average speed.
        let flat = try ramped.applying(.setSpeedCurve(item: "left", curve: nil, keepDuration: false)).project
        #expect(try item(flat, "left").speedCurve == nil && item(flat, "left").speed == 2)

        let linked = try ProjectFixtures.linkedPair()
        let both = try linked.applying(.setSpeedCurve(item: "v", curve: ramp, keepDuration: false)).project
        #expect(try item(both, "a").speedCurve == ramp && item(both, "a").duration == item(both, "v").duration)
        let round = try ProjectFixtures.undoRedo(.setSpeedCurve(item: "left", curve: ramp, keepDuration: false), on: project)
        #expect(round.matches(original: project))
    }

    @Test("Split and trim keep each part on the same source with its part of the ramp")
    func splitAndTrim() throws {
        let ramp = try curve([(0, 1), (0.5, 3), (1, 1)])
        let ramped = try ProjectFixtures.twoClips()
            .applying(.setSpeedCurve(item: "left", curve: ramp, keepDuration: false)).project
        let split = try ramped.applying(.split(item: "left", atFrame: 15, newID: "tail")).project
        // The first half plays 1 s of 60 fps source in 0.5 s of timeline.
        #expect(try item(split, "tail").sourceIn == 60)
        #expect(try item(split, "left").speedCurve?.points.map(\.speed) == [1, 3])
        #expect(try item(split, "tail").speedCurve?.points.map(\.speed) == [3, 1])
        #expect(try item(split, "left").speed == 2 && item(split, "tail").speed == 2)

        let shorter = try ramped.applying(.trim(item: "left", edge: .end, toFrame: 15, ripple: true)).project
        #expect(try item(shorter, "left").speedCurve?.points.map(\.speed) == [1, 3])
        let start = try ramped.applying(.trim(item: "left", edge: .start, toFrame: 15, ripple: false)).project
        #expect(try item(start, "left").sourceIn == 60)
        #expect(try item(start, "left").speedCurve?.points.map(\.speed) == [3, 1])
        // Lengthening holds the end speed: 10 more frames at 1× add 1/3 s of source.
        let longer = try ramped.applying(.trim(item: "left", edge: .end, toFrame: 40, ripple: true)).project
        let extended = try item(longer, "left")
        #expect(abs(extended.sourceSeconds(afterFrames: 40, fps: longer.fps) - (2 + 1.0 / 3)) < 1e-9)
        #expect(abs(extended.timelineFrames(atSourceSeconds: 1, fps: longer.fps) - 15) < 1e-6)
    }

    @Test("setSpeedCurve and setSource round-trip through JSON; presets decode by name")
    func codec() throws {
        let ramp = try curve([(0, 1), (0.5, 3), (1, 1)])
        let operation = EditOperation.setSpeedCurve(item: "left", curve: ramp, keepDuration: true)
        #expect(try EditOperation(json: operation.json) == operation)
        let source = EditOperation.setSource(item: "v", media: "m2", sourceIn: 4, reversed: .object(["media": .string("m")]))
        #expect(try EditOperation(json: source.json) == source)
        let preset = try EditOperation(json: .object([
            "op": .string("setSpeedCurve"), "item": .string("left"), "preset": .string("hero"),
        ]))
        #expect(preset == .setSpeedCurve(item: "left", curve: SpeedCurve.preset("hero"), keepDuration: false))
    }

    @Test("Validation rejects a speed that is not the curve's average")
    func validation() throws {
        var project = try ProjectFixtures.twoClips()
            .applying(.setSpeedCurve(item: "left", curve: try curve([(0, 1), (1, 3)]), keepDuration: false)).project
        project.tracks[0].items[0].fields["speed"] = .number(1.2)
        #expect(throws: ProjectError.self) { try project.validate() }
    }
}
