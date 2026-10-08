import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Clip items (P2-H5): footage in the library, such as a generated B-roll shot. Placing one copies its file into the
/// project's `clips` folder (once per content), imports it and places it like `media place`, as one undo step; the
/// copy belongs to the project, so removing the item from the library never breaks the timeline.
extension ProjectDocument {
    /// A new item's params with what its file measures (audio #78, sticker #64, clip), or nil for kinds that measure
    /// nothing.
    func measuredItemParams(
        _ kind: LibraryKind, _ params: [String: JSONValue], file: URL
    ) async throws -> [String: JSONValue]? {
        switch kind {
        case .audio: try await audioItemParams(params, file: file)
        case .sticker: try await stickerItemParams(params, file: file)
        case .clip: try await clipItemParams(params, file: file)
        default: nil
        }
    }

    /// A new clip's params from its file: `seconds`, `width`, `height` and `hasAudio` as measured, merged over
    /// `params` so a provider's own keys stay.
    func clipItemParams(_ params: [String: JSONValue], file: URL) async throws -> [String: JSONValue] {
        do { try LibraryClip.validate(file: file.lastPathComponent, label: file.lastPathComponent) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        let kind = LibraryClip.isImage(file.lastPathComponent) ? "image" : "video"
        let probe: (media: Media, frames: Int)
        do {
            probe = try await Self.importedMedia(
                url: file, kind: kind, projectFPS: project.fps, root: file.deletingLastPathComponent())
        } catch {
            throw RPCFailure(-32602, "\(file.lastPathComponent) is not a movie or image BashCut can read")
        }
        var params = params
        if let width = probe.media.width, let height = probe.media.height {
            params["width"] = .integer(width)
            params["height"] = .integer(height)
        }
        params["hasAudio"] = .bool(probe.media.hasAudio == true)
        if kind == "video" { params["seconds"] = .number((probe.media.durationSeconds * 1_000).rounded() / 1_000) }
        return params
    }

    /// The library panels' place for a clip: its revision and timeline item.
    func placeLibraryClipItem(_ item: LibraryItem, _ placement: LibraryPlacement) async throws -> (revision: Int, itemID: String) {
        let placed = try await placeLibraryClip(item, placement).object
        return (placed["rev"]?.int ?? project.revision, placed["item"]?.string ?? "")
    }

    /// Project media for a clip's file, copied into `clips/` first (named by its content, so the same file is copied
    /// once), with the item's licence and provenance; reused when the project already has it.
    private func libraryClipMedia(_ item: LibraryItem) async throws -> (media: Media, kind: String) {
        guard item.kind == .clip else { throw RPCFailure(-32602, "\(item.reference) is not a clip") }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before adding a clip from the library")
        }
        guard let file = libraryCatalog.fileURL(of: item) else { throw RPCFailure(-32602, "\(item.reference) has no file") }
        let digest = item.scope.isWritable ? item["fileSHA256"]?.string : nil
        let url = try await LibraryWorker.shared.run {
            try LibraryStore.projectCopy(of: file, root: root, folder: LibraryClip.projectFolder, sha256: digest)
        }
        let kind = LibraryClip.isImage(url.lastPathComponent) ? "image" : "video"
        var imported: Media
        do {
            imported = try await Self.importedMedia(url: url, kind: kind, projectFPS: project.fps, root: root).media
        } catch {
            throw RPCFailure(-32602, "\(item.reference)'s file is not a movie or image BashCut can read")
        }
        imported.fields.merge(Self.libraryRights(item)) { _, rights in rights }
        return (project.existingMedia(like: imported) ?? imported, kind)
    }

    /// `library place` for a clip: its file copied into `clips/`, imported and placed on `placement.trackID` or the
    /// main layer at the playhead or `placement.frame`, trimmed to `placement.duration`, spilling onto a free layer
    /// when that range is taken. Counts the use.
    func placeLibraryClip(_ item: LibraryItem, _ placement: LibraryPlacement) async throws -> JSONValue {
        let (media, kind) = try await libraryClipMedia(item)
        let isNew = !project.media.contains { $0.id == media.id }
        let length = media.placementFrames(in: project.fps)
        let duration = placement.duration.map { kind == "image" ? $0 : min($0, length) } ?? length
        guard duration > 0 else { throw RPCFailure(-32602, "\(item.reference) is too short") }
        let itemID = UUID().uuidString
        let trackID: String
        do {
            var planner = LayerPlanner(project)
            if isNew { try planner.add([.addMedia(media)]) }
            let target = try placement.trackID ?? defaultTrackID(forKind: kind)
            try planner.placeMedia(
                media, on: target, at: placement.frame ?? project.insertionFrame(trackID: target, playhead: playhead),
                duration: duration, itemID: itemID)
            let revision = try commitPlan(
                planner, label: String(localized: "Add clip"), author: placement.author,
                baseRevision: placement.baseRevision)
            trackID = project.tracks.first { $0.items.contains { $0.id == itemID } }?.id ?? target
            if isNew { emitMediaImported([media.id], author: placement.author) }
            selectedTrackID = trackID
            selectedID = itemID
            recordLibraryUse(item)
            var result: [String: JSONValue] = [
                "rev": .integer(revision), "item": .string(itemID), "track": .string(trackID),
                "media": .string(media.id), "duration": .integer(duration), "library": .string(item.reference),
            ]
            if let asked = placement.duration, asked > duration {
                result["note"] = .string("The clip is shorter than asked, so it plays once")
            }
            if placement.position != nil || placement.size != nil {
                result["note"] = .string("position and size apply to image, animated and video stickers only")
            }
            return .object(result)
        } catch let failure as RPCFailure { throw failure } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
    }
}
