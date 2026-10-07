import BashCutProject
import BashCutStorage
import Foundation
import Testing

/// The append-only run log (P1-D6).
struct RunLogTests {
    @Test("Entries append with their time, number and run; reads filter by run, kind and limit")
    func appendAndRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = RunLog(projectRoot: folder)
        #expect(log.entries().isEmpty)
        try log.append(["kind": .string("note"), "text": .string("before")])
        try log.append(["kind": .string("start")])
        try log.append(["kind": .string("gate"), "gate": .string("G1"), "event": .string("approved")])
        try log.append(["kind": .string("start")])
        try log.append(["kind": .string("round"), "round": .integer(1), "fixed": .integer(2), "left": .integer(1)])
        try log.append(["kind": .string("round"), "round": .integer(2), "fixed": .integer(1), "left": .integer(0)])
        let current = log.read().object
        #expect(current["runs"] == .integer(2))
        #expect(current["entries"]?.array.count == 3)
        #expect(log.read(run: "1").object["entries"]?.array.first?.object["kind"] == .string("start"))
        #expect(log.read(run: "all", kind: "round", limit: 1).object["entries"]?.array.first?.object["round"] == .integer(2))
        let first = try #require(log.entries().first)
        #expect(first["n"] == .integer(0) && first["run"] == .integer(0) && first["time"]?.string != nil)
        #expect(throws: (any Error).self) { try log.append(["text": .string(String(repeating: "x", count: 70_000))]) }
        #expect(log.entries().count == 6)
    }
}
