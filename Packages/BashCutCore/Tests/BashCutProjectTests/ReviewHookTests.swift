import Testing

@testable import BashCutProject

/// The opening and close as facts (#467, P0-B11).
struct ReviewHookTests {
    @Test("Opening and close facts: words, titles, captions, cuts, described subjects and sizes")
    func facts() throws {
        let layout = ReviewLayoutTests()
        var project = layout.project([layout.text("cap", "xin chào", at: 20)])
        project.media = [
            Media(fields: [
                "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
                "frames": .integer(900),
                "description": .object(["shots": .array([
                    .object(["start": .number(0), "end": .number(10), "size": .string("WS"), "subjects": .array([.string("chợ")])]),
                    .object(["start": .number(10), "end": .number(30), "size": .string("CU"), "subjects": .array([.string("bánh mì")])]),
                ])]),
            ])
        ]
        let main = project.tracks.firstIndex { $0.role == TrackRole.main }!
        project.tracks[main].items = [
            Item(id: "a", media: "m", at: 0, duration: 90), Item(id: "b", media: "m", at: 90, duration: 120, sourceIn: 300),
        ]
        project.tracks.insert(Track(id: "titles", kind: TrackKind.text, role: "titles"), at: 0)
        project.tracks[0].items = [layout.text("hook", "Ăn gì ở chợ?", at: 0), layout.text("cta", "Theo dõi nhé", at: 150)]
        let words = [ReviewSync.WordSpan(at: 12, end: 20, text: "xin"), ReviewSync.WordSpan(at: 20, end: 30, text: "chào")]
        let json = ReviewHook.json(project, context: layout.context(bottom: 300), words: words).object
        let opening = try #require(json["opening"]).object
        #expect(opening["hookSeconds"] == .null)
        #expect(opening["firstWords"]?.object["frame"] == .integer(12) && opening["firstWords"]?.object["text"] == .string("xin chào"))
        #expect(opening["firstTitle"]?.object["text"] == .string("Ăn gì ở chợ?"))
        #expect(opening["firstCaption"]?.object["item"] == .string("cap"))
        #expect(opening["firstCut"]?.object["frame"] == .integer(90))
        let subjects = try #require(opening["described"]?.object["subjects"]?.array).map(\.object)
        #expect(subjects.map { $0["name"] } == [.string("chợ"), .string("bánh mì")])
        #expect(subjects[1]["firstFrame"] == .integer(90) && subjects[1]["onScreenSeconds"] == .number(4))
        let close = try #require(json["close"]).object
        #expect(close["lastTitle"]?.object["item"] == .string("cta") && close["lastTitle"]?.object["edges"] != nil)
        #expect(close["lastWords"]?.object["frame"] == .integer(30))
        #expect(close["lastCut"]?.object["frame"] == .integer(90))
    }
}
