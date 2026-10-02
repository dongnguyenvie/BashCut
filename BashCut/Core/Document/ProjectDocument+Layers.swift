import BashCutAutomation
import BashCutProject
import Foundation

/// Layer editing shared by the timeline UI and automation. Core `LayerPlanner` applies the layer rules:
/// visual layers above audio, one main layer, and occupied ranges spilling onto free or new layers.
extension ProjectDocument {
    /// Adds an empty layer where `Project.defaultTrackIndex(kind:)` puts it.
    @discardableResult
    func addLayer(
        kind: String, role: String? = nil, name: String? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, trackID: String) {
        let defaultRoles = [
            "video": TrackRole.overlay, Track.adjustmentKind: TrackRole.adjustment, "text": TrackRole.captions,
            "audio": TrackRole.sfx,
        ]
        guard let defaultRole = defaultRoles[kind] else { throw ProjectError.invalid("Unknown layer kind \(kind)") }
        let role = role ?? defaultRole
        guard role != TrackRole.main else { throw ProjectError.invalid("A project has exactly one main layer") }
        var track = Track(id: project.newTrackID(kind: kind), kind: kind, role: role)
        track.name = name ?? "\(role.capitalized) \(project.tracks.filter { $0.role == role }.count + 1)"
        let revision = try commit(
            .addTrack(track: track, atIndex: project.defaultTrackIndex(kind: kind)), label: "Add \(kind) layer",
            author: author, baseRevision: baseRevision)
        return (revision, track.id)
    }

    /// Places media on a layer (the main layer by default) at a frame (the playhead, or the end of a
    /// magnetic layer), spilling onto another layer when that range is occupied.
    @discardableResult
    func placeMedia(
        _ media: Media, trackID: String? = nil, at frame: Int? = nil, itemID: String = UUID().uuidString,
        author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, trackID: String) {
        let trackID = try trackID ?? project.requireTrack(role: TrackRole.main, kind: "video").id
        let duration = Int((Double(media.frames) / media.fps.value * project.fps.value).rounded(.down))
        guard duration > 0 else { throw ProjectError.invalid("Media is too short") }
        var planner = LayerPlanner(project)
        try planner.placeMedia(
            media, on: trackID, at: frame ?? project.insertionFrame(trackID: trackID, playhead: playhead),
            duration: duration, itemID: itemID)
        let revision = try commitPlan(planner, label: "Insert media", author: author, baseRevision: baseRevision)
        let used = project.tracks.first { $0.items.contains { $0.id == itemID } }?.id ?? trackID
        let audio = project.tracks.first { $0.items.contains { $0.id == itemID + "-audio" } }?.id
        DebugLog.write(
            "layers", "place \(mediaSummary(media)) requested=\(trackID) used=\(used)"
                + (used == trackID ? "" : " (SPILLED)")
                + " linkedAudio=\(audio ?? "none (needs video layer, hasAudio=true and a dialogue layer)")")
        return (revision, used)
    }

    /// Moves an item and its linked partner, spilling onto free or new layers instead of overlapping.
    @discardableResult
    func moveItem(
        _ itemID: String, to trackID: String, at frame: Int, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, trackID: String) {
        var planner = LayerPlanner(project)
        try planner.move(itemID, to: trackID, at: frame)
        let revision = try commitPlan(planner, label: "Move clip", author: author, baseRevision: baseRevision)
        let used = project.tracks.first { $0.items.contains { $0.id == itemID } }?.id ?? trackID
        DebugLog.write(
            "layers", "move \(itemID) requested=\(trackID)@\(frame) used=\(used)" + (used == trackID ? "" : " (SPILLED)"))
        return (revision, used)
    }

    @discardableResult
    func commitPlan(_ planner: LayerPlanner, label: String, author: Author, baseRevision: Int?) throws -> Int {
        let operations = planner.operations
        let operation = operations.count == 1 ? operations[0] : .group(label: label, author: author, ops: operations)
        return try commit(operation, label: label, author: author, baseRevision: baseRevision)
    }

    func deleteSelectedTrack(author: Author = .user) throws {
        guard let id = selectedTrackID else { throw ProjectError.invalid("Select a layer first") }
        try commit(.deleteTrack(track: id), label: "Delete layer", author: author)
        if !project.tracks.contains(where: { $0.id == id }) { selectedTrackID = nil }
    }

    /// Moves the selected layer up (`offset` > 0) or down on screen, within its visual or audio band.
    func moveSelectedTrack(by offset: Int, author: Author = .user) throws {
        guard let id = selectedTrackID, let index = project.tracks.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Select a layer first")
        }
        let track = project.tracks[index]
        // Visual layers are stored back to front and shown reversed; audio layers are shown in order.
        let band = project.trackBand(kind: track.kind)
        let destination = min(band.upperBound - 1, max(band.lowerBound, index + (track.isVisual ? offset : -offset)))
        DebugLog.write(
            "layers", "reorder \(id) offset=\(offset) index \(index)→\(destination) band=\(band.lowerBound)..<\(band.upperBound)")
        guard destination != index else { return }
        try commit(.moveTrack(track: id, toIndex: destination), label: "Reorder layer", author: author)
    }

    /// Deletes the gap containing `frame` on `trackID` (the main layer by default).
    @discardableResult
    func closeGap(
        at frame: Int, trackID: String? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        let trackID = try trackID ?? project.requireTrack(role: TrackRole.main, kind: "video").id
        let operation = try project.closingGap(on: trackID, containing: frame)
        return try commit(operation, label: "Delete gap", author: author, baseRevision: baseRevision)
    }

    /// Sets a layer's hidden, muted or locked switch (nil leaves it as is) as one undoable edit.
    @discardableResult
    func setLayerSwitches(
        _ trackID: String, hidden: Bool? = nil, muted: Bool? = nil, locked: Bool? = nil, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> Int {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else {
            throw ProjectError.invalid("Unknown layer \(trackID)")
        }
        var patch: [String: JSONValue] = [:]
        if let hidden { patch["hidden"] = .bool(hidden) }
        if let muted { patch["muted"] = .bool(muted) }
        if let locked { patch["locked"] = .bool(locked) }
        guard !patch.isEmpty else { throw ProjectError.invalid("Pass --hidden, --muted or --locked") }
        let label = locked.map { $0 ? "Lock \(track.name)" : "Unlock \(track.name)" }
            ?? hidden.map { $0 ? "Hide \(track.name)" : "Show \(track.name)" }
            ?? (muted == true ? "Mute \(track.name)" : "Unmute \(track.name)")
        return try commit(
            .setTrackProperties(track: trackID, patch: patch), label: label, author: author, baseRevision: baseRevision)
    }

    // MARK: Automation

    func registerLayerCommands() {
        handleAuthored("timeline.close-gap") { document, arguments, author in
            let revision = try document.closeGap(
                at: arguments.int("atFrame"), trackID: arguments.optionalString("track"), author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
        handleAuthored("layers.set") { document, arguments, author in
            let revision = try document.setLayerSwitches(
                arguments.string("track"), hidden: arguments.optionalBool("hidden"),
                muted: arguments.optionalBool("muted"), locked: arguments.optionalBool("locked"), author: author,
                baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
        handleAuthored("layers.add") { document, arguments, author in
            let result = try document.addLayer(
                kind: arguments.string("kind"), role: arguments.optionalString("role"),
                name: arguments.optionalString("name"), author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "track": .string(result.trackID)])
        }
        handleAuthored("media.place") { document, arguments, author in
            let mediaID = try arguments.string("media")
            guard let media = document.project.media.first(where: { $0.id == mediaID }) else {
                throw RPCFailure(-32602, "Unknown media \(mediaID)")
            }
            let itemID = UUID().uuidString
            let result = try document.placeMedia(
                media, trackID: arguments.optionalString("track"), at: arguments.optionalInt("atFrame"),
                itemID: itemID, author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "item": .string(itemID), "track": .string(result.trackID)])
        }
        handleAuthored("timeline.move") { document, arguments, author in
            let result = try document.moveItem(
                arguments.string("item"), to: arguments.string("track"), at: arguments.int("atFrame"),
                author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "track": .string(result.trackID)])
        }
    }
}
