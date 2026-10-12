import Testing
@testable import BashCutProject

@Test("Transitions require an adjacent video cut and are undoable")
func transitionEditing() throws {
    let media = Media(fields: [
        "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json,
        "frames": .integer(300),
    ])
    var project = Project(name: "Transitions", fps: FrameRate(30, 1))
    project = try project.applying(.group(label: "clips", author: .user, ops: [
        .addMedia(media),
        .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
        .insert(track: "v1", item: Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60)),
    ])).project
    let edited = try project.applying(
        .upsertTransition(id: "cut-a-b", kind: "dissolve", from: "a", to: "b", duration: 15))
    #expect(edited.project.transitions.first?.kind == "dissolve")
    #expect(try edited.project.applying(edited.inverse).project.transitions.isEmpty)
}

@Test("An agent's upsertTransition may leave out the id and name the cut with between (#507-18)")
func transitionWithoutID() throws {
    let media = Media(fields: [
        "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json,
        "frames": .integer(300),
    ])
    var project = Project(name: "Transitions", fps: FrameRate(30, 1))
    project = try project.applying(.group(label: "clips", author: .user, ops: [
        .addMedia(media),
        .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
        .insert(track: "v1", item: Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60)),
    ])).project
    let op = try EditOperation(json: .object([
        "op": .string("upsertTransition"), "between": .array([.string("a"), .string("b")]),
        "kind": .string("dissolve"), "duration": .integer(15),
    ]))
    #expect(try EditOperation(json: op.json) == op)
    project = try project.applying(op).project
    #expect(project.transitions.map(\.id) == ["transition-a-b"])
    // A second one at the same cut updates it in place and keeps its id.
    project = try project.applying(.upsertTransition(id: "named", kind: "dissolve", from: "a", to: "b", duration: 10)).project
    project = try project.applying(.upsertTransition(id: "", kind: "wipe", from: "a", to: "b", duration: 20)).project
    #expect(project.transitions.map(\.id) == ["named"] && project.transitions.first?.kind == "wipe")
    #expect(throws: ProjectError.self) {
        try EditOperation(json: .object([
            "op": .string("upsertTransition"), "between": .array([.string("a")]), "kind": .string("dissolve"),
            "duration": .integer(15),
        ]))
    }
}

@Test("Moving a clip away removes its now-invalid transition")
func transitionReconciliation() throws {
    let media = Media(fields: [
        "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json,
        "frames": .integer(300),
    ])
    var project = Project(name: "Transitions", fps: FrameRate(30, 1))
    project = try project.applying(.group(label: "fixture", author: .user, ops: [
        .addMedia(media),
        .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
        .insert(track: "v1", item: Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60)),
        .upsertTransition(id: "cut", kind: "wipe", from: "a", to: "b", duration: 12),
    ])).project
    let moved = try project.applying(.move(item: "b", toTrack: "v2", atFrame: 60)).project
    #expect(moved.transitions.isEmpty)
}
