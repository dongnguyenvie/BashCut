import BashCutProject

/// Validates the exact edit pipeline on a value copy without history, disk writes, preview rebuilds or hooks.
public enum TimelineDryRun {
    private struct Position: Equatable {
        let track: String
        let index: Int
        let item: Item
    }

    public static func evaluate(_ operation: EditOperation, on project: Project, baseRevision: Int) throws -> JSONValue {
        let next = try project.applying(operation, baseRevision: baseRevision).project
        func positions(_ value: Project) -> [String: Position] {
            Dictionary(uniqueKeysWithValues: value.tracks.flatMap { track in
                track.items.enumerated().map { ($0.element.id, Position(track: track.id, index: $0.offset, item: $0.element)) }
            })
        }
        let before = positions(project), after = positions(next)
        let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
        let oldTracks = Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id, $0) })
        let newTracks = Dictionary(uniqueKeysWithValues: next.tracks.map { ($0.id, $0) })
        let changedTracks = Set(oldTracks.keys).union(newTracks.keys).filter { oldTracks[$0] != newTracks[$0] }.sorted()
        return .object([
            "dryRun": .bool(true), "rev": .integer(project.revision), "projectedRev": .integer(next.revision),
            "duration": .integer(next.duration), "previousDuration": .integer(project.duration),
            "changedItems": .array(changed.map(JSONValue.string)),
            "changedTracks": .array(changedTracks.map(JSONValue.string)),
            "addedTracks": .array(next.tracks.filter { oldTracks[$0.id] == nil }.map { .string($0.id) }),
            "removedTracks": .array(project.tracks.filter { newTracks[$0.id] == nil }.map { .string($0.id) })
        ])
    }
}
