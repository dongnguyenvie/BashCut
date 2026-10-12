import Testing

@testable import BashCutProject

/// `textStyle.lines` (text phase 2): editing, validation and the review's smallest line.
struct TextLineStylesTests {
    @Test("Setting merges into a line, null removes a field, clear and trailing nulls trim the list")
    func setting() throws {
        var style = try TextLineStyles.setting(["size": .number(0.06)], line: 1, patch: ["font": .string("Georgia"), "scale": .number(0.5)])
        #expect(style["lines"] == .array([.null, .object(["font": .string("Georgia"), "scale": .number(0.5)])]))
        style = try TextLineStyles.setting(style, line: 1, patch: ["font": .null])
        #expect(TextLineStyles.style(style, line: 1) == ["scale": .number(0.5)])
        #expect(TextLineStyles.scale(style, line: 1) == 0.5 && TextLineStyles.scale(style, line: 0) == 1)
        style = try TextLineStyles.setting(style, line: 1, patch: [:], clear: true)
        #expect(style["lines"] == nil && style["size"] == .number(0.06))
        #expect(throws: ProjectError.self) { try TextLineStyles.setting([:], line: 0, patch: ["weight": .number(700)]) }
        #expect(throws: ProjectError.self) { try TextLineStyles.setting([:], line: 0, patch: ["scale": .number(9)]) }
        #expect(TextLineStyles.index(-1, count: 3) == 2 && TextLineStyles.index(3, count: 3) == nil)
    }

    @Test("Validation rejects unknown fields and bad values; items without lines are unchanged")
    func validation() throws {
        var project = Project(name: "Lines", fps: FrameRate(30, 1))
        var item = Item(id: "t", at: 0, duration: 30)
        item["text"] = .string("A\nB")
        item["textStyle"] = .object(["lines": .array([.null, .object(["fill": .string("#FFD60A"), "scale": .number(0.6)])])])
        project = try project.applying(.insert(track: "t1", item: item)).project
        var bad = item
        bad["textStyle"] = .object(["lines": .array([.object(["fill": .string("yellow")])])])
        #expect(throws: ProjectError.self) { try project.applying(.setProperties(item: "t", patch: ["textStyle": bad["textStyle"]!])) }
        bad["textStyle"] = .object(["lines": .string("x")])
        #expect(throws: ProjectError.self) { try project.applying(.setProperties(item: "t", patch: ["textStyle": bad["textStyle"]!])) }
    }

    @Test("The review's smallest line follows a line scaled down")
    func smallestLine() {
        var item = Item(id: "t", at: 0, duration: 30)
        item["text"] = .string("A\nB")
        item["textStyle"] = .object(["lines": .array([.null, .object(["scale": .number(0.4)])])])
        let box = TimelineReview.TextBox(item: item, lines: 2, points: 100, minX: 0, maxX: 10, minY: 0, maxY: 10)
        #expect(box.smallestPoints == 40)
    }
}
