import BashCutProjectFixtures
import Testing
@testable import BashCutProject

struct HistoryNoOpTests {
    @Test("An edit that changes nothing keeps the revision and adds no undo step")
    func unchangedEdit() throws {
        var history = ProjectHistory(project: try ProjectFixtures.twoClips("a", "b"))
        try history.apply(.setProperties(item: "a", patch: ["opacity": .number(0.5)]), label: "Fade")
        try history.undo()
        try history.redo()
        let revision = history.project.revision

        let changed = try history.apply(.setProperties(item: "a", patch: ["opacity": .number(0.5)]), label: "Same")
        #expect(!changed)
        #expect(history.project.revision == revision)
        #expect(history.undoEntries.map(\.label) == ["Fade"])
        // The redo stack survives too: nothing happened that could branch history.
        try history.undo()
        #expect(try !history.apply(.group(label: "Empty", author: .claude, ops: []), label: "Empty"))
        #expect(history.canRedo)

        let result = try history.project.applying(.setProperties(item: "a", patch: [:]), baseRevision: history.project.revision)
        #expect(!result.changed && result.project == history.project)
        // Restoring the same content under another revision (an external reload) still moves the revision.
        var reloaded = history.project
        reloaded.revision += 10
        #expect(try history.project.applying(.restore(reloaded)).changed)
        #expect(throws: ProjectError.self) {
            try history.apply(.setProperties(item: "a", patch: [:]), label: "Stale", baseRevision: revision + 5)
        }
    }
}
