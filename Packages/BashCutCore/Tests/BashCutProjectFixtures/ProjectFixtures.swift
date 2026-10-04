import BashCutProject

/// Shared project fixtures for the core test targets. Every fixture is built through `applying`, so it
/// obeys the same validation as real edits.
public enum ProjectFixtures {
    /// A media entry with integer frames at a rational rate.
    public static func media(
        _ id: String = "m", path: String = "clip.mov", frames: Int = 600, fps: FrameRate = FrameRate(60, 1),
        kind: String? = nil, hasAudio: Bool? = nil
    ) -> Media {
        var fields: [String: JSONValue] = [
            "id": .string(id), "path": .string(path), "frames": .integer(frames), "fps": fps.json,
        ]
        if let kind { fields["kind"] = .string(kind) }
        if let hasAudio { fields["hasAudio"] = .bool(hasAudio) }
        return Media(fields: fields)
    }

    /// Two adjacent 60-frame clips on the main track of a 30 fps project, cut from one 60 fps source.
    public static func twoClips(
        _ first: String = "left", _ second: String = "right", sourceIn: (Int, Int) = (0, 120),
        name: String = "Two clips"
    ) throws -> Project {
        try Project(name: name, fps: FrameRate(30, 1)).applying(
            .group(
                label: "Setup", author: .user,
                ops: [
                    .addMedia(media()),
                    .insert(track: "v1", item: Item(id: first, media: "m", at: 0, duration: 60, sourceIn: sourceIn.0)),
                    .insert(track: "v1", item: Item(id: second, media: "m", at: 60, duration: 60, sourceIn: sourceIn.1)),
                ])
        ).project
    }

    /// A 30 fps project with picture `v` on the main track linked to its sound `a` on the dialogue track.
    public static func linkedPair() throws -> Project {
        var video = Item(id: "v", media: "m", at: 0, duration: 60)
        video.fields["linkedAudio"] = .string("a")
        var audio = Item(id: "a", media: "m", at: 0, duration: 60)
        audio.fields["linkedVideo"] = .string("v")
        return try Project(name: "Linked", fps: FrameRate(30, 1)).applying(
            .group(
                label: "Setup", author: .user,
                ops: [
                    .addMedia(media(path: "source.mov", fps: FrameRate(30, 1), kind: "video", hasAudio: true)),
                    .insert(track: "a1", item: audio), .insert(track: "v1", item: video),
                ])
        ).project
    }

    /// Applies `operation` through `ProjectHistory`, then undoes and redoes it.
    public static func undoRedo(_ operation: EditOperation, on project: Project) throws -> UndoRedo {
        var history = ProjectHistory(project: project)
        try history.apply(operation, label: "Round trip")
        let applied = history.project
        try history.undo()
        let undone = history.project
        try history.redo()
        return UndoRedo(applied: applied, undone: undone, redone: history.project)
    }

    public struct UndoRedo: Sendable {
        public let applied: Project
        public let undone: Project
        public let redone: Project

        /// Both comparisons ignore the revision, which every step advances.
        public func matches(original: Project) -> Bool {
            Self.content(undone) == Self.content(original) && Self.content(redone) == Self.content(applied)
        }

        private static func content(_ project: Project) -> Project {
            var copy = project
            copy.revision = 0
            return copy
        }
    }
}

/// Benchmark lines that docs/status/implementation.md quotes come from test logs. This is the only place tests
/// write to standard output; diagnostics belong in assertions.
public enum TestMeasurement {
    public static func report(_ line: String) { print(line) }
}
