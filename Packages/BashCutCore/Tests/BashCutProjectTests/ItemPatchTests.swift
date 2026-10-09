import Foundation
import Testing

@testable import BashCutProject

/// `patchItems`: deep-merge restyles expanded into `setProperties` (Phase 2 restyle).
struct ItemPatchTests {
    private func project() throws -> Project {
        var first = Item(id: "c1", at: 0, duration: 30)
        first["text"] = .string("One")
        first["textStyle"] = .object(["color": .string("#FFFFFF"), "size": .number(0.05)])
        var second = Item(id: "c2", at: 30, duration: 30)
        second["text"] = .string("Two")
        second["textPreset"] = .string("bold")
        return try Project(name: "Patch").applying(.group(label: "Setup", author: .user, ops: [
            .insert(track: "t1", item: first), .insert(track: "t1", item: second),
        ])).project
    }

    @Test("A selector restyles every matching item; objects merge and null deletes a key")
    func selector() throws {
        let project = try project()
        let ops = try ItemPatch.expand([.object([
            "op": .string("patchItems"), "select": .object(["trackRole": .string("captions")]),
            "patch": .object(["textStyle": .object(["color": .string("#FFD400"), "size": .null])]),
        ])], in: project)
        #expect(ops.count == 2)
        let first = ops[0].object["patch"]?.object["textStyle"]
        #expect(first == .object(["color": .string("#FFD400")]))
        let second = ops[1].object["patch"]?.object["textStyle"]
        #expect(second == .object(["color": .string("#FFD400")]))
        let applied = try project.applying(.group(label: "Restyle", author: .agent, ops: ops.map { try EditOperation(json: $0) }))
        #expect(applied.project.tracks.flatMap(\.items).allSatisfy { $0["textStyle"]?.object["color"] == .string("#FFD400") })
    }

    @Test("Two patches in one batch compose; bad selectors are refused")
    func compose() throws {
        let project = try project()
        let ops = try ItemPatch.expand([
            .object(["op": .string("patchItems"), "items": .array([.string("c1")]),
                     "patch": .object(["textStyle": .object(["align": .string("left")])])]),
            .object(["op": .string("patchItems"), "select": .object(["textPreset": .string("bold")]),
                     "patch": .object(["textStyle": .object(["shadow": .object(["blur": .number(4)])])])]),
            .object(["op": .string("patchItems"), "items": .array([.string("c1")]),
                     "patch": .object(["textStyle": .object(["tracking": .number(0.1)])])]),
        ], in: project)
        #expect(ops.count == 3)
        #expect(ops[1].object["item"] == .string("c2"))
        #expect(ops[2].object["patch"]?.object["textStyle"]?.object.keys.sorted() == ["align", "color", "size", "tracking"])
        for bad: JSONValue in [
            .object(["op": .string("patchItems"), "select": .object(["role": .string("x")]), "patch": .object(["a": .integer(1)])]),
            .object(["op": .string("patchItems"), "select": .object(["track": .string("nope")]), "patch": .object(["a": .integer(1)])]),
            .object(["op": .string("patchItems"), "items": .array([.string("c1")])]),
        ] {
            #expect(throws: ProjectError.self) { try ItemPatch.expand([bad], in: project) }
        }
    }
}
