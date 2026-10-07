import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutProject
import CoreMedia
import Foundation

/// The sticker library (#64): emoji, image, animated and video-with-alpha stickers. Placing an image-like sticker
/// copies its file into the project's `stickers` folder (once per content), imports it and places it on the Overlay
/// layer, sized and positioned, as one undo step; the copy belongs to the project, so removing the sticker from the
/// library never breaks the timeline.
extension ProjectDocument {
    // MARK: Adding

    /// A new sticker's params from its file: the kind (an image with several frames is `animated`, a movie must have
    /// an alpha channel), pixel size and frame count, merged over `params`.
    func stickerItemParams(_ params: [String: JSONValue], file: URL) async throws -> [String: JSONValue] {
        let kind: String
        do { kind = try LibrarySticker.kind(ofFile: file.lastPathComponent, label: file.lastPathComponent) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        var params = params
        if kind == "video-alpha" {
            if let given = params["stickerKind"]?.string, given != "video-alpha" {
                throw RPCFailure(-32602, "\(file.lastPathComponent) is a movie, not a \(given) sticker")
            }
            let movie = try await Self.alphaMovie(file, label: file.lastPathComponent)
            params["stickerKind"] = .string("video-alpha")
            params["width"] = .integer(movie.width)
            params["height"] = .integer(movie.height)
            return params
        }
        do { return try LibrarySticker.imageParams(params, file: file) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
    }

    /// The picture size of a movie with an alpha channel (HEVC with alpha, or ProRes 4444 with alpha); throws for a
    /// movie without one, which would cover the picture below it.
    nonisolated static func alphaMovie(_ url: URL, label: String) async throws -> (width: Int, height: Int) {
        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack?
        do { track = try await asset.loadTracks(withMediaType: .video).first } catch {
            throw RPCFailure(-32602, "\(label) is not a movie BashCut can read")
        }
        guard let track else { throw RPCFailure(-32602, "\(label) has no picture") }
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []
        guard descriptions.contains(where: hasAlpha) else {
            throw RPCFailure(
                -32602,
                "\(label) has no alpha channel; a video sticker must be HEVC with alpha or ProRes 4444 with alpha, "
                    + "or else place it as a clip with media import")
        }
        let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
        return (Int(abs(size.width).rounded()), Int(abs(size.height).rounded()))
    }

    nonisolated private static func hasAlpha(_ description: CMFormatDescription) -> Bool {
        if let flag = CMFormatDescriptionGetExtension(
            description, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel) as? Bool, flag
        {
            return true
        }
        let codec = CMFormatDescriptionGetMediaSubType(description)
        guard codec == kCMVideoCodecType_AppleProRes4444 || codec == kCMVideoCodecType_AppleProRes4444XQ else {
            return false
        }
        let depth = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_Depth) as? Int
        return depth == 32
    }

    // MARK: Placing

    private func librarySticker(_ item: LibraryItem) throws -> LibrarySticker {
        guard item.kind == .sticker else { throw RPCFailure(-32602, "\(item.reference) is not a sticker") }
        do { return try LibrarySticker(params: item.params, file: item.file, label: item.reference) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
    }

    /// Whether `item` is a sticker placed as media (image, animated or video-alpha), not as emoji text.
    func isMediaSticker(_ item: LibraryItem) -> Bool {
        item.kind == .sticker && (try? librarySticker(item))?.isMedia == true
    }

    /// Project media for a sticker's file, copied into `stickers/` first (named by its content, so the same file is
    /// copied once), and reused when the project already has it. Also says how many frames an image file has.
    private func libraryStickerMedia(_ item: LibraryItem, sticker: LibrarySticker) async throws -> (media: Media, frames: Int) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before adding a sticker from the library")
        }
        guard let file = libraryCatalog.fileURL(of: item) else { throw RPCFailure(-32602, "\(item.reference) has no file") }
        let digest = item.scope.isWritable ? item["fileSHA256"]?.string : nil
        let url = try await LibraryWorker.shared.run {
            try LibraryStore.projectCopy(of: file, root: root, folder: LibrarySticker.projectFolder, sha256: digest)
        }
        var imported: (media: Media, frames: Int)
        var frames = 1
        if sticker.stickerKind == "video-alpha" {
            _ = try await Self.alphaMovie(url, label: item.reference)
            imported = try await Self.importedMedia(url: url, kind: "video", projectFPS: project.fps, root: root)
            imported.media["alpha"] = .bool(true)
        } else {
            guard let probe = LibrarySticker.probeImage(url) else {
                throw RPCFailure(-32602, "\(item.reference)'s file is not an image BashCut can read")
            }
            frames = probe.frames
            imported = try Self.importedImage(url: url, projectFPS: project.fps, root: root)
        }
        imported.media[TransitionPreset.soundLibraryField] = .string(item.reference)
        imported.media.fields.merge(Self.libraryRights(item)) { _, rights in rights }
        return (project.existingMedia(like: imported.media) ?? imported.media, frames)
    }

    /// `library place` for an image, animated or video-alpha sticker: its file copied into the project, imported and
    /// placed on the Overlay layer (added when missing) at the playhead or `placement.frame`, `size` of the frame
    /// width wide at `position` (the sticker's defaults, else 30% in the centre), as one undo step.
    func placeLibrarySticker(_ item: LibraryItem, _ placement: LibraryPlacement) async throws -> JSONValue {
        let sticker = try librarySticker(item)
        let (media, frames) = try await libraryStickerMedia(item, sticker: sticker)
        let placed: StickerPlacement
        do {
            placed = try project.stickerPlacePlan(
                media, sticker: sticker, at: placement.frame ?? playhead, duration: placement.duration,
                position: placement.position, size: placement.size, trackID: placement.trackID)
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        let isNew = !project.media.contains { $0.id == media.id }
        let revision = try commitPlan(
            placed.planner, label: String(localized: "Add sticker"), author: placement.author,
            baseRevision: placement.baseRevision)
        if isNew { emitMediaImported([media.id], author: placement.author) }
        selectedTrackID = placed.trackID
        selectedID = placed.itemID
        recordLibraryUse(item)
        var result: [String: JSONValue] = [
            "rev": .integer(revision), "item": .string(placed.itemID), "track": .string(placed.trackID),
            "media": .string(media.id), "duration": .integer(placed.duration), "library": .string(item.reference),
            "stickerKind": .string(sticker.stickerKind),
            "transform": .object([
                "zoom": .number(placed.zoom), "pan": .number(placed.pan), "tilt": .number(placed.tilt),
            ]),
        ]
        var notes: [String] = []
        if sticker.stickerKind == "animated" || frames > 1 {
            notes.append(
                "BashCut shows animated stickers as their first frame for now; export the animation as a movie with "
                    + "alpha (HEVC with alpha or ProRes 4444) for motion")
        }
        if placed.shortened { notes.append("The sticker movie is shorter than asked, so it plays once") }
        if !notes.isEmpty { result["note"] = .string(notes.joined(separator: ". ")) }
        return .object(result)
    }

    // MARK: Saving the selection

    /// A sticker's params and file from the overlay item `itemID` (the selection by default): an emoji text item, or
    /// an image or alpha movie item with its size, position and length.
    func stickerSelection(itemID: String?) throws -> (params: [String: JSONValue], file: URL?) {
        guard let id = itemID ?? selectedID else {
            throw RPCFailure(-32602, "Select an image or emoji overlay item, or pass --item")
        }
        guard let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }) else {
            throw RPCFailure(-32602, "Unknown item \(id)")
        }
        if item["text"] != nil {
            do { return (try LibrarySelection.sticker(item, media: nil, project: project), nil) } catch {
                throw RPCFailure.from(error, fallbackCode: -32602)
            }
        }
        guard let media = item.mediaID.flatMap({ mediaID in project.media.first { $0.id == mediaID } }) else {
            throw RPCFailure(-32602, "\(id) is not an image or emoji item")
        }
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before saving its stickers to the library")
        }
        let file = try MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace)
        let frames = media.isImage ? LibrarySticker.probeImage(file)?.frames ?? 1 : 1
        do {
            return (try LibrarySelection.sticker(item, media: media, project: project, frames: frames), file)
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
    }

    // MARK: Removing

    /// Removes a saved item (`library remove` and the panels' Remove from Library). Files of the item that the open
    /// project's media still points at directly are kept, and the result lists them under `kept`; placed copies of
    /// library files live in the project folder and are never touched.
    func removeLibraryItem(_ item: LibraryItem, author: Author) async throws -> JSONValue {
        guard item.scope.isWritable else {
            throw RPCFailure(-32602, "\(item.reference) is \(item.scope.rawValue) and cannot be removed")
        }
        let store = try libraryCatalog.store(item.scope)
        let used: [URL] = fileURL.map { file in
            let root = file.deletingLastPathComponent()
            return project.media.compactMap {
                try? MediaPathResolver.resolve($0.path, projectRoot: root, workspaceRoot: settings.workspace)
            }
        } ?? []
        return try await libraryChange(
            "library.remove", scope: item.scope, author: author, arguments: ["id": item.reference, "name": item.name]
        ) {
            let (removed, kept) = try store.remove(item.id, keeping: used)
            var result: [String: JSONValue] = ["removed": .string(removed.reference)]
            if !kept.isEmpty {
                result["kept"] = .array(kept.map(JSONValue.string))
                result["note"] = .string("Kept the files this project's media still uses")
            }
            return .object(result)
        }
    }
}
