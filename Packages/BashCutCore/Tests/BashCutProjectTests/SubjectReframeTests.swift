import Testing

@testable import BashCutProject

/// `clip.reframe` (P3-J1): subject-aware framing from stored face boxes, with its gate and fallback.
struct SubjectReframeTests {
    /// A 1920×1080, 30 fps source on a 1080×1920 canvas: filled, the picture is 3413 px wide, 1166.7 px to spare
    /// on each side.
    func setup(duration: Int = 90) -> (Project, Media, Item) {
        var project = Project(name: "Reframe", fps: FrameRate(30, 1))
        project["format"] = .object(["width": .integer(1080), "height": .integer(1920), "fps": FrameRate(30, 1).json])
        let media = Media(fields: [
            "id": .string("m"), "path": .string("m.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(300), "width": .integer(1920), "height": .integer(1080),
        ])
        return (project, media, Item(id: "a", media: "m", at: 0, duration: duration, sourceIn: 30))
    }

    func face(_ x: Double, width: Double = 0.1, confidence: Double = 0.9) -> MediaSubjects.Box {
        MediaSubjects.Box(x: x, y: 0.3, width: width, height: 0.2, confidence: confidence)
    }

    /// One picture per source second from 0 to 9, each with the face `at(second)` (nil: no face).
    func subjects(_ at: (Int) -> MediaSubjects.Box?) -> MediaSubjects {
        MediaSubjects(samples: (0..<10).map { second in
            MediaSubjects.Sample(seconds: Double(second), faces: at(second).map { [$0] } ?? [])
        }, step: 1)
    }

    @Test("Locked: one pan that centres the median face, fill on, full coverage, no keys")
    func locked() throws {
        let (project, media, item) = setup()
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { _ in face(0.65) }, options: .init())
        #expect(plan.applied == "reframe" && plan.reason == nil)
        #expect(plan.patch["fill"] == .bool(true))
        // Face centre at 0.7 of 1920 → 0.2 × 1920 × (1920/1080) = 682.7 px left of centre.
        let pan = try #require(plan.patch["transform"]?.object["pan"]?.double)
        #expect(abs(pan - -682.7) < 0.2)
        #expect(plan.patch["keyframes"] == .null)
        // The item plays source seconds 1…3.97: pictures at 1, 2, 3 and 4 (4 is the nearest to its last frame).
        #expect(plan.coverage.samples == 4 && plan.coverage.subjectSamples == 4)
        #expect((plan.coverage.mean ?? 0) > 0.999 && (plan.coverage.min ?? 0) > 0.999)
    }

    @Test("A face at the picture's edge is kept with the pan clamped to the picture")
    func clamped() throws {
        let (project, media, item) = setup()
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { _ in face(0.92, width: 0.06) }, options: .init())
        let pan = try #require(plan.patch["transform"]?.object["pan"]?.double)
        #expect(abs(pan - -1166.7) < 0.2)
        #expect((plan.coverage.mean ?? 0) > 0.999)
    }

    @Test("Cut: a new framing held from where the face moves, with hold keys")
    func cut() throws {
        let (project, media, item) = setup(duration: 240)
        var options = SubjectReframe.Options()
        options.mode = .cut
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { $0 < 5 ? face(0.2) : face(0.7) }, options: options)
        #expect(plan.segments.count == 2)
        // The picture at source second 5 is the nearest one past 4.5 s: item frame (4.5 − 1) × 30 + 1.
        #expect(plan.segments[1].frame == 106)
        let pan = try #require(plan.patch["keyframes"]?.object["pan"]?.array)
        #expect(pan.count == 2 && pan[0].object["ease"] == .string("hold"))
        #expect((plan.coverage.mean ?? 0) > 0.999)
        #expect(plan.previewFrames.contains(0) && plan.previewFrames.contains(106))
    }

    @Test("Cut: a move shorter than minHoldSeconds keeps the framing")
    func cutHold() throws {
        let (project, media, item) = setup(duration: 240)
        var options = SubjectReframe.Options()
        options.mode = .cut
        options.minHoldSeconds = 8
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { $0 < 5 ? face(0.2) : face(0.7) }, options: options)
        // One framing for both places keeps the later one (the median) and loses the earlier: under the gate, fit.
        #expect(plan.applied == "fit" && plan.patch["fill"] == .bool(false))
        #expect(abs((plan.coverage.mean ?? 0) - 5.0 / 9) < 0.01)
    }

    @Test("Follow: linear pan keys at each picture, smoothed")
    func follow() throws {
        let (project, media, item) = setup(duration: 240)
        var options = SubjectReframe.Options()
        options.mode = .follow
        options.smoothSeconds = 0
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { face(0.1 + Double($0) * 0.05) }, options: options)
        let pan = try #require(plan.patch["keyframes"]?.object["pan"]?.array)
        #expect(pan.count == 9 && pan[0].object["ease"] == .string("linear") && pan[0].object["frame"] == .integer(0))
        let values = pan.compactMap { $0.object["value"]?.double }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test("Too few pictures with a face: fit, with the reason and coverage; refuse throws instead")
    func gate() throws {
        let (project, media, item) = setup()
        let sparse = subjects { $0 == 1 ? face(0.5) : nil }
        let plan = try SubjectReframe.plan(item, media: media, project: project, subjects: sparse, options: .init())
        #expect(plan.applied == "fit" && plan.patch["fill"] == .bool(false))
        #expect(plan.reason?.contains("minSubjectShare") == true)
        #expect(plan.patch["transform"]?.object["pan"] == .number(0))
        #expect(plan.coverage.subjectSamples == 1 && plan.coverage.samples == 4)
        var options = SubjectReframe.Options()
        options.fallback = .refuse
        #expect(throws: SubjectReframe.Refused.self) {
            try SubjectReframe.plan(item, media: media, project: project, subjects: sparse, options: options)
        }
        options.minSubjectShare = 0.2
        let lenient = try SubjectReframe.plan(item, media: media, project: project, subjects: sparse, options: options)
        #expect(lenient.applied == "reframe")
    }

    @Test("Low-confidence boxes are not subjects; nothing stored for the clip's source falls back")
    func confidenceAndMissing() throws {
        let (project, media, item) = setup()
        let unsure = subjects { _ in face(0.5, confidence: 0.2) }
        #expect(try SubjectReframe.plan(item, media: media, project: project, subjects: unsure, options: .init()).applied == "fit")
        let elsewhere = MediaSubjects(samples: [.init(seconds: 9, faces: [face(0.5)])], step: 1)
        let plan = try SubjectReframe.plan(item, media: media, project: project, subjects: elsewhere, options: .init())
        #expect(plan.applied == "fit" && plan.coverage.samples == 0)
    }

    @Test("Existing zoom, pan and tilt keys are replaced; other keys stay")
    func keepsOtherKeys() throws {
        let (project, media, base) = setup()
        var item = base
        item["keyframes"] = .object([
            "zoom": .array([.object(["frame": .integer(0), "value": .number(1.3)])]),
            "opacity": .array([.object(["frame": .integer(0), "value": .number(0.5)])]),
        ])
        let plan = try SubjectReframe.plan(
            item, media: media, project: project, subjects: subjects { _ in face(0.4) }, options: .init())
        #expect(plan.patch["keyframes"]?.object.keys.sorted() == ["opacity"])
    }

    @Test("Stored boxes merge by picture time and round-trip as JSON")
    func storage() {
        let first = subjects { _ in face(0.2) }
        let second = MediaSubjects(samples: [.init(seconds: 3, faces: [face(0.6)]), .init(seconds: 12, faces: [])], step: 1)
        let merged = first.merging(second)
        #expect(merged.samples.count == 11)
        #expect(merged.sample(near: 3)?.faces.first?.x == 0.6)
        #expect(merged.sample(near: 3.4)?.seconds == 3 && merged.sample(near: 10.6) == nil)
        #expect(MediaSubjects(json: merged.json) == merged)
    }
}
