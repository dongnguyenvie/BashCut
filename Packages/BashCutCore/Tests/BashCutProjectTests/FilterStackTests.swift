import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Filter stacks: looks with a grade and a LUT (#79)")
struct FilterStackTests {
    private static let warm: [String: JSONValue] = [
        "exposure": .number(0.2), "contrast": .number(1.1), "saturation": .number(0.9), "lutStrength": .number(0.6),
    ]

    /// A LUT as the app makes it from a look's .cube: a copy in `luts/` that remembers the file's hash.
    private static func libraryLUT(_ id: String = "lut-1", hash: String = "abc123", name: String = "Warm film") -> ColorLUT {
        var lut = ColorLUT(id: id, name: name, path: "luts/library-\(hash).cube", size: 2)
        lut[ColorLUT.libraryHashField] = .string(hash)
        lut[ColorLUT.libraryItemField] = .string("user:warm-film")
        return lut
    }

    private static func operation(_ planner: LayerPlanner) -> EditOperation {
        planner.operations.count == 1 ? planner.operations[0] : .group(label: "Look", author: .user, ops: planner.operations)
    }

    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("filter-stacks-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("A stack checks its grade, LUT name and file; old looks stay valid")
    func validation() throws {
        let stack = try FilterStack(params: ["color": .object(Self.warm), "lutName": .string("Warm film")])
        #expect(stack == FilterStack(color: Self.warm, lutName: "Warm film"))
        #expect(try FilterStack(params: stack.params) == stack)
        #expect(FilterStack(color: Self.warm).params == ["color": .object(Self.warm)])
        let bad: [([String: JSONValue], String)] = [
            ([:], "params.color"),
            (["color": .string("warm")], "params.color"),
            (["color": .object(["lutStrength": .number(2)])], "lutStrength"),
            (["color": .object(["exposure": .string("1")])], "exposure"),
            (["color": .object([:]), "lutName": .string("")], "lutName"),
            (["color": .object([:]), "lutName": .integer(1)], "lutName"),
        ]
        for (params, message) in bad {
            let item = LibraryItem(id: "l", kind: .look, name: "L", params: params)
            #expect(throws: ProjectError.self) { try item.validate() }
            do { try item.validate() } catch { #expect(error.localizedDescription.contains(message)) }
        }
        // A look's file is its LUT, so it must be a .cube.
        var image = LibraryItem(id: "l", kind: .look, name: "L", params: stack.params)
        image["file"] = .string("files/l/v1/look.png")
        #expect(throws: ProjectError.self) { try image.validate() }
        image["file"] = .string("files/l/v1/Look.CUBE")
        try image.validate()
        // Looks saved before filter stacks: just a grade, even with a stray project LUT ID.
        try LibraryItem(id: "old", kind: .look, name: "Old", params: ["color": .object(["contrast": .number(1.1)])]).validate()
        try LibraryItem(
            id: "older", kind: .look, name: "Older", params: ["color": .object(["lut": .string("x"), "saturation": .integer(0)])]
        ).validate()
        // Built-in looks: the same IDs and grades as the built-in project looks, plus a few more.
        for item in LibraryBuiltIns.looks { try item.validate() }
        for look in ColorLook.builtIn {
            let item = try #require(LibraryBuiltIns.looks.first { $0.id == look.id })
            #expect(try FilterStack(params: item.params).color == look.color)
        }
    }

    @Test("A look without a LUT places and applies its grade as before")
    func plainLook() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let stack = FilterStack(color: ["saturation": .number(1.2)])
        let applied = try project.applying(Self.operation(try project.filterStackApplyPlan(stack, to: "a"))).project
        let expected = try project.applying(
            .setProperties(item: "a", patch: ["color": .object(["saturation": .number(1.2)])])).project
        #expect(applied.tracks == expected.tracks)
        #expect(applied.colorLUTs.isEmpty)
        let placed = try project.applying(Self.operation(
            try project.filterStackPlacePlan(stack, item: Item.adjustment(id: "adj", at: 0, duration: 30)))).project
        let adjustment = try #require(placed.tracks.first(where: \.isAdjustment)?.items.first)
        #expect(adjustment.id == "adj")
        #expect(adjustment["color"] == .object(["saturation": .number(1.2)]))
        #expect(throws: ProjectError.self) { try project.filterStackApplyPlan(stack, to: "missing") }
    }

    @Test("Placing a look with a LUT is one undo step that adds the LUT and the adjustment")
    func placeWithLUT() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let stack = FilterStack(color: Self.warm, lutName: "Warm film")
        let lut = Self.libraryLUT()
        let planner = try project.filterStackPlacePlan(stack, lut: lut, item: Item.adjustment(id: "adj", at: 0, duration: 60))
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(planner), label: "Warm film")
        #expect(history.undoEntries.count == 1)
        let placed = history.project
        #expect(placed.colorLUTs.map(\.id) == ["lut-1"])
        #expect(placed.libraryLUT(sha256: "abc123")?.id == "lut-1")
        let adjustment = try #require(placed.tracks.first(where: \.isAdjustment)?.items.first)
        var grade = Self.warm
        grade["lut"] = .string("lut-1")
        #expect(adjustment["color"] == .object(grade))
        try history.undo()
        var undone = history.project
        undone["rev"] = project["rev"]  // revisions only move forward
        #expect(undone == project)
        #expect(!history.canUndo)
        // A LUT already in the project is reused, not added again.
        let again = try placed.filterStackPlacePlan(stack, lut: lut, item: Item.adjustment(id: "adj-2", at: 60, duration: 60))
        let twice = try placed.applying(Self.operation(again)).project
        #expect(twice.colorLUTs.count == 1)
        #expect(twice.tracks.flatMap(\.items).filter { $0["color"]?.object["lut"] == .string("lut-1") }.count == 2)
    }

    @Test("Applying a look with a LUT to a clip is one undo step and replaces its grade")
    func applyWithLUT() throws {
        var project = try ProjectFixtures.twoClips("a", "b")
        project = try project.applying(
            .setProperties(item: "a", patch: ["color": .object(["exposure": .number(-1), "saturation": .integer(0)])])).project
        let stack = FilterStack(color: ["contrast": .number(1.2), "lutStrength": .number(0.5)], lutName: "Teal")
        let planner = try project.filterStackApplyPlan(stack, lut: Self.libraryLUT(), to: "a")
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(planner), label: "Teal")
        #expect(history.undoEntries.count == 1)
        let clip = try #require(history.project.tracks.flatMap(\.items).first { $0.id == "a" })
        #expect(clip["color"] == .object([
            "contrast": .number(1.2), "lutStrength": .number(0.5), "lut": .string("lut-1"),
        ]))
        try history.undo()
        #expect(history.project.colorLUTs.isEmpty)
        #expect(history.project.tracks == project.tracks)
    }

    @Test("Save selection keeps the whole stack, and it round-trips through a store into another project")
    func saveSelectionRoundTrip() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectLUT = ColorLUT(id: "warm", name: "Warm sunset", path: "luts/warm.cube", size: 2)
        var clip = Item(at: 0, duration: 30)
        clip["color"] = .object(Self.warm.merging(["lut": .string("warm")]) { $1 })
        // With its LUT: grade, strength and the LUT's name, not its project ID.
        let params = try LibrarySelection.params(.look, item: clip, lut: projectLUT)
        #expect(params == FilterStack(color: Self.warm, lutName: "Warm sunset").params)
        // Without the LUT (unknown or not passed): the grade alone, as before.
        var plain = Self.warm
        plain["lutStrength"] = nil
        #expect(try LibrarySelection.params(.look, item: clip) == ["color": .object(plain)])
        let other = ColorLUT(id: "other", name: "Other", path: "luts/other.cube", size: 2)
        #expect(try LibrarySelection.params(.look, item: clip, lut: other) == ["color": .object(plain)])
        // A LUT alone is a look too.
        var lutOnly = Item(at: 0, duration: 30)
        lutOnly["color"] = .object(["lut": .string("warm")])
        #expect(try LibrarySelection.params(.look, item: lutOnly, lut: projectLUT)
            == FilterStack(color: [:], lutName: "Warm sunset").params)
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.look, item: lutOnly) }

        // Saved with the .cube as its file, as the app does.
        let cube = folder.appendingPathComponent("sources/warm.cube")
        try FileManager.default.createDirectory(at: cube.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("LUT_3D_SIZE 2\n".utf8).write(to: cube)
        let store = LibraryStore.project(root: folder.appendingPathComponent("project"))
        let catalog = LibraryCatalog(builtIn: [], user: nil, project: store)
        try catalog.add(LibraryItem(id: "warm-film", kind: .look, name: "Warm film", params: params), into: .project, file: cube)
        let read = try catalog.item("project:warm-film")
        try read.validate(root: store.root)
        #expect(read.file?.hasSuffix("warm.cube") == true)
        let hash = try #require(read["fileSHA256"]?.string)
        #expect(hash == (try LibraryStore.sha256(of: cube)))

        // Used in another project: the same grade, pointing at that project's copy of the LUT.
        let stack = try FilterStack(params: read.params)
        let target = try ProjectFixtures.twoClips("x", "y")
        let lut = Self.libraryLUT("copied", hash: hash, name: try #require(stack.lutName))
        let applied = try target.applying(Self.operation(try target.filterStackApplyPlan(stack, lut: lut, to: "x"))).project
        let graded = try #require(applied.tracks.flatMap(\.items).first { $0.id == "x" })
        #expect(graded["color"] == .object(Self.warm.merging(["lut": .string("copied")]) { $1 }))
        #expect(try LibrarySelection.params(.look, item: graded, lut: applied.colorLUTs.first) == params)
    }
}
