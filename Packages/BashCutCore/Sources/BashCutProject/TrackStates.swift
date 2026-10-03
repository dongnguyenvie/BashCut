import Foundation

// Layer switches from the timeline header: hide a visual layer, mute an audio layer, lock any layer.
// They are plain track fields changed with `setTrackProperties`, so they undo and round-trip like any edit.

extension Track {
    /// A hidden visual layer is left out of preview and export.
    public var isHidden: Bool { self["hidden"] == .bool(true) }
    /// A muted layer contributes no sound and does not duck music.
    public var isMuted: Bool { self["muted"] == .bool(true) }
    /// Nothing on a locked layer can change until it is unlocked.
    public var isLocked: Bool { self["locked"] == .bool(true) }

    func validateStates() throws {
        for key in ["hidden", "muted", "locked"] {
            if let value = self[key], case .bool = value { continue }
            if self[key] != nil { throw ProjectError.invalid("track.\(id).\(key): expected boolean") }
        }
        if self["hidden"] != nil, !isVisual {
            throw ProjectError.invalid("track.\(id): only visual layers can be hidden")
        }
        if self["muted"] != nil, isVisual {
            throw ProjectError.invalid("track.\(id): only audio layers can be muted")
        }
    }
}

extension Project {
    /// Rejects an edit that changed items on a layer that is locked before and after it. Undo (`restore`)
    /// is exempt so history keeps working; unlocking is a track property change, which this never blocks.
    func enforceLocks(after next: Project, operation: EditOperation) throws {
        if case .restore = operation { return }
        for track in tracks where track.isLocked {
            guard let after = next.tracks.first(where: { $0.id == track.id }) else {
                throw ProjectError.invalid("\(track.name) is locked; unlock it first")
            }
            if after.isLocked, after.items != track.items {
                throw ProjectError.invalid("\(track.name) is locked; unlock it first")
            }
        }
    }
}
