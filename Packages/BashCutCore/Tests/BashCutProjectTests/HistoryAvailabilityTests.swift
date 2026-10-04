import BashCutProjectFixtures
import Foundation
import Testing
@testable import BashCutProject

struct HistoryAvailabilityTests {
    @Test("Undo availability follows history without materializing snapshot arrays")
    func availability() throws {
        var history = ProjectHistory(project: Project(name: "History availability"))
        #expect(!history.canUndo && !history.canRedo && history.lastUndo == nil)
        for index in 0..<ProjectHistory.maximumDepth {
            try history.apply(.setProjectProperties(patch: ["name": .string("Step \(index)")]), label: "Step \(index)")
        }
        #expect(history.canUndo && !history.canRedo)
        #expect(history.lastUndo?.label == "Step 199")
        try history.undo()
        #expect(history.canUndo && history.canRedo && history.lastUndo?.label == "Step 198")

        let iterations = 10_000
        var oldCount = 0, newCount = 0
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            if !history.undoEntries.isEmpty { oldCount += 1 }
            if !history.redoEntries.isEmpty { oldCount += 1 }
        }
        let copies = start.duration(to: .now)
        let directStart = ContinuousClock.now
        for _ in 0..<iterations {
            if history.canUndo { newCount += 1 }
            if history.canRedo { newCount += 1 }
        }
        let direct = directStart.duration(to: .now)
        #expect(oldCount == iterations * 2 && newCount == oldCount)
        TestMeasurement.report("History availability \(iterations) pairs: arrays \(copies), direct \(direct)")

        try history.redo()
        #expect(history.canUndo && !history.canRedo && history.lastUndo?.label == "Step 199")
        for _ in 0..<ProjectHistory.maximumDepth { try history.undo() }
        #expect(!history.canUndo && history.canRedo && history.lastUndo == nil)
        try history.apply(.setProjectProperties(patch: ["name": .string("Branch")]), label: "Branch")
        #expect(history.canUndo && !history.canRedo && history.lastUndo?.label == "Branch")
    }
}
