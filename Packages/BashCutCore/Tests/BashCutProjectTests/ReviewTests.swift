import Testing

@testable import BashCutProject

struct ReviewTests {
    @Test("Review finds picture gaps, long caption lines and missing tagged speech")
    func rules() throws {
        var project = Project(name: "Review")
        let media = Media(fields: [
            "id": .string("m"), "path": .string("video.mov"), "frames": .integer(300),
            "fps": FrameRate().json,
        ])
        var caption = Item(id: "caption", at: 0, duration: 90)
        caption["text"] = .string(String(repeating: "a", count: 50))
        project = try project.applying(
            .group(
                label: "fixture", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(id: "clip", media: "m", at: 30, duration: 60)),
                    .insert(track: "t1", item: caption),
                ])
        ).project
        let issues = TimelineReview.run(project)
        #expect(Set(issues.map(\.id)) == ["gap-clip", "caption-caption", "safe-side-caption", "coverage"])
    }

    @Test("Review flags each missing font once, at its first text item (#415)")
    func missingFont() throws {
        var project = Project(name: "Fonts")
        var ops: [EditOperation] = []
        for (index, font) in ["Gone-Bold", "Gone-Bold", "Here-Regular"].enumerated() {
            var text = Item(id: "t\(index)", at: index * 30, duration: 30)
            text["text"] = .string("Xin chào")
            text["textStyle"] = .object(["font": .string(font)])
            ops.append(.insert(track: "t1", item: text))
        }
        project = try project.applying(.group(label: "fixture", author: .user, ops: ops)).project
        let issues = TimelineReview.run(project, fontAvailable: { $0 == "Here-Regular" })
        #expect(issues.filter { $0.title == "Missing font" }.map(\.id) == ["font-t0"])
        #expect(!TimelineReview.run(project).contains { $0.title == "Missing font" })
    }

    @Test("textStyle font and colours are validated (#413)")
    func textStyleRules() throws {
        let project = Project(name: "Style")
        for (style, valid) in [
            (["font": JSONValue.string("Montserrat-ExtraBold"), "fill": .string("#FFD400"), "stroke": .string("#000000")], true),
            (["fill": JSONValue.string("yellow")], false),
            (["stroke": JSONValue.string("#00000")], false),
            (["font": JSONValue.string("")], false),
        ] {
            var text = Item(id: "t", at: 0, duration: 30)
            text["text"] = .string("A")
            text["textStyle"] = .object(style)
            let result = Result { try project.applying(.insert(track: "t1", item: text)) }
            #expect(((try? result.get()) != nil) == valid, "\(style)")
        }
    }

    @Test("Review flags voiceover closer than 0.3 seconds to tagged speech across layers")
    func voiceoverProximity() throws {
        var project = Project(name: "Voice review", fps: FrameRate(30, 1))
        let media = Media(fields: [
            "id": .string("m"), "path": .string("video.mov"), "frames": .integer(300),
            "fps": FrameRate(30, 1).json,
        ])
        var speech = Item(id: "speech", media: "m", at: 0, duration: 30)
        speech["tag"] = .object(["role": .string("speech")])
        let close = Item(id: "close", media: "m", at: 38, duration: 5)
        let boundary = Item(id: "boundary", media: "m", at: 39, duration: 5)
        var extraVoice = Track(id: "a5", kind: "audio", role: "voiceover")
        extraVoice.items = [close, boundary]
        project = try project.applying(
            .group(
                label: "fixture", author: .user,
                ops: [.addMedia(media), .insert(track: "v1", item: speech)]
            )
        ).project
        project.tracks.append(extraVoice)

        let overlapIDs = Set(
            TimelineReview.run(project).filter { $0.id.hasPrefix("overlap-") }.map(\.id))
        #expect(overlapIDs == ["overlap-close"])
        #expect(abs(TimelineReview.speechCoverage(project) - 36.0 / 44.0) < 0.0001)
    }

    @Test("Review flags captions that look like a recognition loop")
    func recognitionLoops() throws {
        var project = Project(name: "Loops", fps: FrameRate(30, 1))
        func caption(_ id: String, _ text: String, at: Int, duration: Int = 60) -> Item {
            var item = Item(id: id, at: at, duration: duration)
            item["text"] = .string(text)
            return item
        }
        let captions = [
            caption("long", "một câu rất dài", at: 0, duration: 330),
            caption("repeat", "à à à à", at: 400),
            caption("half", "và nói và nói và nói", at: 500),
            caption("fine", "không không, mình nói tiếp nhé", at: 600),
        ]
        project = try project.applying(
            .group(label: "fixture", author: .user, ops: captions.map { .insert(track: "t1", item: $0) })).project
        let loops = TimelineReview.run(project).map(\.id).filter { $0.hasPrefix("loop-") }
        #expect(loops == ["loop-long", "loop-repeat", "loop-half"])
    }
}
