import Foundation
import Testing

@testable import BashCutProject

@Suite("History coalescing")
struct HistoryCoalescingTests {
    private func history() throws -> ProjectHistory {
        var project = Project(name: "Coalescing")
        project = try project.applying(
            .group(
                label: "Setup", author: .user,
                ops: [
                    .addMedia(Media(fields: [
                        "id": .string("m1"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json,
                        "frames": .integer(300),
                    ])),
                    .insert(track: "v1", item: Item(id: "c1", media: "m1", at: 0, duration: 90)),
                ])
        ).project
        return ProjectHistory(project: project)
    }

    private func opacity(_ value: Double) -> EditOperation {
        .setProperties(item: "c1", patch: ["opacity": .number(value)])
    }

    @Test("Continuous edits on one key become one undo step that restores the original value")
    func mergesContinuousInput() throws {
        var history = try history()
        let start = Date()
        for (index, value) in [0.9, 0.8, 0.7, 0.6].enumerated() {
            try history.apply(
                opacity(value), label: "Opacity", coalescingKey: "c1:opacity",
                now: start.addingTimeInterval(Double(index) * 0.1))
        }
        #expect(history.undoEntries.count == 1)
        #expect(history.project.tracks[0].items[0]["opacity"] == .number(0.6))
        try history.undo()
        #expect(history.project.tracks[0].items[0]["opacity"] == nil)
    }

    @Test("A pause, another key, another author or an intervening edit starts a new step")
    func boundaries() throws {
        var history = try history()
        let start = Date()
        try history.apply(opacity(0.9), label: "Opacity", coalescingKey: "k", now: start)
        try history.apply(opacity(0.8), label: "Opacity", coalescingKey: "k", now: start.addingTimeInterval(2))
        #expect(history.undoEntries.count == 2)
        try history.apply(opacity(0.7), label: "Opacity", coalescingKey: "other", now: start.addingTimeInterval(2.1))
        #expect(history.undoEntries.count == 3)
        try history.apply(
            opacity(0.6), label: "Opacity", author: .claude, coalescingKey: "other",
            now: start.addingTimeInterval(2.2))
        #expect(history.undoEntries.count == 4)
        try history.apply(.setProperties(item: "c1", patch: ["muted": .bool(true)]), label: "Mute")
        try history.apply(opacity(0.5), label: "Opacity", author: .claude, coalescingKey: "other",
            now: start.addingTimeInterval(2.3))
        #expect(history.undoEntries.count == 6)
    }

    @Test("Undo ends coalescing so the next edit cannot swallow the undone step")
    func undoBreaksCoalescing() throws {
        var history = try history()
        let start = Date()
        try history.apply(opacity(0.9), label: "Opacity", coalescingKey: "k", now: start)
        try history.undo()
        try history.apply(opacity(0.8), label: "Opacity", coalescingKey: "k", now: start.addingTimeInterval(0.1))
        #expect(history.undoEntries.count == 1)
        #expect(history.redoEntries.isEmpty)
    }

    @Test("A rejected edit leaves the merged step and project unchanged")
    func rejectedEdit() throws {
        var history = try history()
        let start = Date()
        try history.apply(opacity(0.9), label: "Opacity", coalescingKey: "k", now: start)
        #expect(throws: (any Error).self) {
            try history.apply(opacity(5), label: "Opacity", coalescingKey: "k", now: start.addingTimeInterval(0.1))
        }
        #expect(history.undoEntries.count == 1)
        #expect(history.project.tracks[0].items[0]["opacity"] == .number(0.9))
    }
}
