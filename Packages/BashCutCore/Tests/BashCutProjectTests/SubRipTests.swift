import Foundation
import Testing

@testable import BashCutProject

struct SubRipTests {
    @Test("Paragraph gaps export as valid SRT without losing text")
    func paragraphs() throws {
        var item = Item(at: 0, duration: 30)
        item["text"] = .string("First\r\n\r\nSecond\n \nThird")
        let project = try Project(name: "Paragraphs").applying(.insert(track: "t1", item: item)).project
        let result = try SubRip.decode(SubRip.encode(project), fps: project.fps)
        #expect(result.count == 1)
        #expect(result.first?.text == "First\nSecond\nThird")
        #expect(project.tracks[2].items.first?.text == item.text)
    }

    private let text =
        "\u{FEFF}1\r\n00:00:00,500 --> 00:00:01,500\r\nĂn ngon ở Buôn Ma Thuột\r\nă â đ ê ô ơ ư\r\n\r\n"
        + "2\r\n00:00:02.000 --> 00:00:03.000\r\nCảm ơn!\r\n"

    @Test("SubRip reads BOM, CRLF, multiline Vietnamese and decimal timestamps")
    func parsing() throws {
        let items = try SubRip.decode(text, fps: FrameRate(30, 1))
        #expect(items.map(\.at) == [15, 60])
        #expect(items.map(\.duration) == [30, 30])
        #expect(items[0].text == "Ăn ngon ở Buôn Ma Thuột\nă â đ ê ô ơ ư")
        #expect(Set(items.map(\.id)).count == 2)
    }

    @Test("Fractional FPS timing round-trips within one millisecond without drift")
    func roundTrip() throws {
        var project = Project(name: "SRT")
        let items = [Item(id: "one", at: 1, duration: 23), Item(id: "two", at: 999999, duration: 2997)]
        for var item in items {
            item["text"] = .string("Tiếng Việt")
            project = try project.applying(.insert(track: "t1", item: item)).project
        }
        let serialized = try SubRip.encode(project)
        let decoded = try SubRip.decode(serialized, fps: project.fps)
        #expect(decoded.map(\.at) == items.map(\.at))
        #expect(decoded.map(\.duration) == items.map(\.duration))
    }

    @Test("Replace and append are atomic undoable edits; malformed imports leave captions intact")
    func importHistory() throws {
        var history = ProjectHistory(project: Project(name: "Captions"))
        try history.apply(history.project.importingSubRip(text), label: "Import")
        let original = history.project
        // Appending the same cues overlaps them, so they go to a second caption layer.
        try history.apply(history.project.importingSubRip(text), label: "Append")
        #expect(history.project.tracks[2].items.count == 2)
        #expect(history.project.tracks[3].role == "captions")
        #expect(history.project.tracks[3].items.count == 2)
        try history.apply(history.project.importingSubRip(text, replace: true), label: "Replace")
        #expect(history.project.tracks[2].items.count == 2)
        #expect(history.project.tracks[3].items.isEmpty)
        try history.undo()
        #expect(history.project.tracks[3].items.count == 2)
        try history.undo()
        #expect(history.project.tracks[2].items == original.tracks[2].items)
        #expect(throws: ProjectError.self) {
            try history.apply(history.project.importingSubRip("invalid", replace: true), label: "Invalid")
        }
        #expect(history.project.tracks[2].items == original.tracks[2].items)
    }

    @Test("Malformed, reversed, subframe and oversized subtitles are rejected")
    func invalid() throws {
        for input in [
            "", "1\ninvalid\nHello", "00:00:02,000 --> 00:00:01,000\nHello",
            "00:99:00,000 --> 00:99:01,000\nHello", "00:00:00,001 --> 00:00:00,002\nHello",
            "00:00:00,000 --> 00:00:01,000", "00:00:00,00 --> 00:00:01,000\nHi",
        ] {
            #expect(throws: ProjectError.self) { try SubRip.decode(input, fps: FrameRate()) }
        }
        #expect(throws: ProjectError.self) {
            try SubRip.decode(String(repeating: "a", count: SubRip.maximumBytes + 1), fps: FrameRate())
        }
    }

    @Test("Generated captions retain provider provenance through apply and undo")
    func generatedProvenance() throws {
        let original = Project(name: "Generated captions")
        var history = ProjectHistory(project: original)
        let provenance: [String: JSONValue] = [
            "plugin": .string("app.bashcut.whisper"),
            "provider": .string("local.whisper"), "version": .string("1.2.0"),
        ]
        try history.apply(
            original.importingSubRip(text, replace: true, provenance: provenance),
            label: "Generate captions")
        let captions = history.project.tracks.first { $0.role == "captions" }?.items ?? []
        #expect(captions.count == 2)
        #expect(captions.allSatisfy { $0["generatedBy"] == .object(provenance) })
        try history.undo()
        #expect(history.project.tracks.first { $0.role == "captions" }?.items.isEmpty == true)
        #expect(history.project.revision == 2)
    }

    @Test("Export sorts cues by time without reordering source items")
    func order() throws {
        var project = Project(name: "Sorted captions")
        for (frame, text) in [(30, "Second"), (0, "First")] {
            var item = Item(at: frame, duration: 30)
            item["text"] = .string(text)
            project = try project.applying(.insert(track: "t1", item: item)).project
        }
        let exported = try SubRip.decode(SubRip.encode(project), fps: project.fps)
        #expect(exported.map(\.text) == ["First", "Second"])
        #expect(project.tracks[2].items.map(\.text) == ["Second", "First"])
    }
}
