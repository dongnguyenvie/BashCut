import Foundation
import Testing

@testable import BashCutProject

/// Shot facts in a closed vocabulary (P0-A4): `media.describe` / `media.description`.
struct MediaDescriptionTests {
    /// A 10 s, 25 fps video media `m` on a 30 fps project.
    func project() -> Project {
        var project = Project(name: "Describe", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: [
                "id": .string("m"), "path": .string("m.mp4"), "kind": .string("video"),
                "fps": .array([.integer(25), .integer(1)]), "frames": .integer(250),
            ])
        ]
        return project
    }

    func shot(_ start: Double, _ end: Double, _ extra: [String: JSONValue] = ["size": .string("MS")]) -> JSONValue {
        var row = extra
        row["start"] = .number(start)
        row["end"] = .number(end)
        return .object(row)
    }

    func description(_ shots: [JSONValue]) -> JSONValue {
        .object(["shots": .array(shots), "describedBy": .string("codex"), "describedAt": .string("2026-10-07T00:00:00Z")])
    }

    @Test("Shots in the vocabulary are stored sorted, read back and undone")
    func store() throws {
        let project = project()
        let value = description([
            shot(4, 10, ["size": .string("CU"), "move": .string("handheld"), "subjects": .array([.string(" cat ")]),
                         "bestMoment": .number(6.5), "looked": .array([.number(9), .number(5)]),
                         "confidence": .number(0.7)]),
            shot(0, 4, ["size": .string("WS"), "angle": .string("high"), "direction": .string("left"), "people": .integer(2)]),
        ])
        let result = try project.applying(.setMediaDescription(media: "m", description: value))
        let stored = try #require(result.project.media[0].shotDescription)
        #expect(stored.shots.map(\.start) == [0, 4])
        #expect(stored.shots[1].subjects == ["cat"])
        #expect(stored.shots[1].looked == [5, 9])
        #expect(stored.describedBy == "codex")
        #expect(stored.describedSeconds == 10)
        let undone = try result.project.applying(result.inverse).project
        #expect(undone.media[0].shotDescription == nil)
        let cleared = try result.project.applying(.setMediaDescription(media: "m", description: nil)).project
        #expect(cleared.media[0].fields["description"] == nil)
    }

    @Test("Open labels and extra fields are kept")
    func open() throws {
        let value = description([shot(0, 2, ["size": .string("medium"), "tags": .array([.string("food")]),
                                            "mood": .string("calm")])])
        let stored = try #require(try project().applying(.setMediaDescription(media: "m", description: value))
            .project.media[0].shotDescription)
        #expect(stored.shots[0].size == "medium")
        #expect(stored.shots[0].json.object["mood"] == .string("calm"))
        #expect(stored.shots[0].tags == ["food"])
    }

    @Test("Bad labels, bad ranges and overlaps are rejected")
    func closed() {
        let project = project()
        let cases: [(JSONValue, String)] = [
            (description([shot(0, 2, ["size": .string("")])]), "size: expected a label"),
            (description([shot(0, 11)]), "start and end"),
            (description([shot(2, 1)]), "start and end"),
            (description([shot(0, 3), shot(2, 5)]), "overlaps"),
            (description([shot(0, 2, ["bestMoment": .number(3)])]), "bestMoment"),
            (description([shot(0, 2, ["confidence": .number(2)])]), "confidence"),
            (description([shot(0, 2, [:])]), "at least one fact"),
            (description([]), "1–5000"),
        ]
        for (value, message) in cases {
            #expect {
                _ = try project.applying(.setMediaDescription(media: "m", description: value))
            } throws: { error in
                (error as? ProjectError)?.localizedDescription.contains(message) == true
            }
        }
        #expect(throws: ProjectError.self) { _ = try project.applying(.setMediaDescription(media: "x", description: nil)) }
    }

    @Test("A stored invalid description fails project validation")
    func validation() {
        var project = project()
        project.media[0].fields["description"] = description([shot(0, 2, ["move": .integer(3)])])
        #expect(throws: ProjectError.self) { try project.validate() }
    }

    @Test("Merge replaces overlapping shots and keeps the rest")
    func merge() throws {
        let stored = try MediaDescription(json: description([shot(0, 3), shot(3, 6), shot(6, 10)]), duration: 10)
        let new = try MediaDescription.shots([shot(2.5, 4, ["size": .string("ECU")])], duration: 10)
        let merged = try stored.merging(new)
        #expect(merged.map(\.start) == [2.5, 6])
        #expect(merged[0].size == "ECU")
    }

    @Test("Coverage counts measured shots that are at least half described")
    func coverage() throws {
        let stored = try MediaDescription(json: description([shot(0, 2), shot(5, 6)]), duration: 10)
        let json = stored.coverage(duration: 10, measured: [(0, 2.5), (2.5, 5), (5, 7), (7, 10)]).object
        #expect(json["shots"] == .integer(2))
        #expect(json["describedShare"] == .number(0.3))
        #expect(json["measuredShots"] == .integer(4))
        #expect(json["coveredShots"] == .integer(2))
        #expect(json["missing"]?.array.compactMap { $0.object["index"]?.int } == [1, 3])
        #expect(stored.coverage(duration: 10, measured: nil).object["measuredShots"] == nil)
    }

    @Test("Review shots carry the facts of the source shot each clip plays most of")
    func reviewShots() throws {
        var project = project()
        project.media[0].fields["description"] = description([
            shot(0, 4, ["size": .string("WS"), "note": .string("establishing")]), shot(4, 10, ["size": .string("CU")]),
        ])
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        // Source 3–6 s (more of it in the CU), then 0–1 s.
        project.tracks[index].items = [
            Item(id: "a", media: "m", at: 0, duration: 90, sourceIn: 75), Item(id: "b", media: "m", at: 90, duration: 30),
        ]
        let shots = try #require(ReviewShots.json(project).object["shots"]?.array).map(\.object)
        let first = try #require(shots[0]["described"]).object
        #expect(first["size"] == .string("CU"))
        #expect(first["start"] == .number(4))
        #expect(shots[1]["described"]?.object["size"] == .string("WS"))
        #expect(shots[1]["described"]?.object["note"] == nil)
    }

    @Test("The operation round-trips through the wire format")
    func wire() throws {
        let value = description([shot(0, 1)])
        let operation = EditOperation.setMediaDescription(media: "m", description: value)
        #expect(try EditOperation(json: operation.json) == operation)
        let cleared = EditOperation.setMediaDescription(media: "m", description: nil)
        #expect(try EditOperation(json: cleared.json) == cleared)
    }
}
