import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import UniformTypeIdentifiers

/// Image stickers (PNG, GIF and other images) kept in one library for every project. Adding one copies it into
/// the project's `stickers` folder, so the project stays self-contained, and places it on an overlay layer.
extension ProjectDocument {
    /// Share of the fitted frame a new sticker takes.
    static let stickerZoom = 0.35

    static var stickerLibraryFolder: URL {
        StorageUsage.supportFolder.appendingPathComponent("Stickers", isDirectory: true)
    }

    /// The library's images, by name.
    static func stickerLibrary() -> [URL] { stickers(in: stickerLibraryFolder) }

    /// The images directly in `folder`, by name.
    static func stickers(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter(StillImageMovie.isImage)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Asks for images and copies them into the library.
    func importStickers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard let urls = ModalCenter.shared.open(panel, name: "import-stickers"), !urls.isEmpty else { return }
        do { try addToStickerLibrary(urls) } catch { message = error.localizedDescription }
    }

    /// Copies images into the library; a file with a name already there is kept as it is.
    func addToStickerLibrary(_ urls: [URL]) throws {
        let folder = Self.stickerLibraryFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in urls {
            guard StillImageMovie.isImage(url) else { throw ProjectError.invalid("\(url.lastPathComponent) is not an image") }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: url, to: destination)
            }
        }
        stickerLibraryRevision += 1
    }

    /// Removes a sticker from the library; projects that used it keep their own copy.
    func removeSticker(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            stickerLibraryRevision += 1
        } catch { message = error.localizedDescription }
    }

    /// Places a sticker at the playhead, as a click in the Stickers panel does.
    func addSticker(_ url: URL) {
        guard fileURL != nil else { return }
        busy = true
        Task {
            defer { busy = false }
            do { _ = try await placeSticker(url) } catch { message = error.localizedDescription }
        }
    }

    /// Places a sticker image at a frame (the playhead by default) on a free overlay layer (a new one when needed),
    /// sticker sized, and selects it.
    @discardableResult
    func placeSticker(
        _ url: URL, at frame: Int? = nil, author: Author = .user, baseRevision: Int? = nil
    ) async throws -> (revision: Int, mediaID: String, itemID: String, trackID: String) {
        guard let root = fileURL?.deletingLastPathComponent() else { throw ProjectError.invalid("Open a saved project first") }
        guard StillImageMovie.isImage(url), FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("No image at \(url.path)")
        }
        var file = url
        // A still is copied into the project; an animated one is written there as a movie by the import.
        if !AnimatedImageMovie.isAnimated(url) {
            let folder = root.appendingPathComponent(AnimatedImageMovie.folder, isDirectory: true)
            file = folder.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: file)
            }
        }
        let imported = try await Self.importedMedia(url: file, kind: "image", projectFPS: project.fps, root: root)
        var planner = LayerPlanner(project)
        let existing = project.media.first { $0.path == imported.media.path }
        let media = existing ?? imported.media
        if existing == nil { try planner.add([.addMedia(media)]) }
        let duration = media.placementFrames(in: project.fps)
        let start = frame ?? playhead
        let itemID = UUID().uuidString
        let trackID = try stickerTrack(&planner, at: start, duration: duration)
        try planner.placeMedia(media, on: trackID, at: start, duration: duration, itemID: itemID)
        try planner.add([
            .setProperties(item: itemID, patch: ["transform": .object(["zoom": .number(Self.stickerZoom)])])
        ])
        let revision = try commitPlan(planner, label: "Add sticker", author: author, baseRevision: baseRevision)
        selectedID = itemID
        if existing == nil { emitMediaImported([media.id], author: author) }
        return (revision, media.id, itemID, trackID)
    }

    /// The frontmost unlocked, visible overlay layer that is free over the range, or a new overlay layer in front
    /// of the other video layers, so a sticker is not hidden behind a full-frame overlay.
    private func stickerTrack(_ planner: inout LayerPlanner, at frame: Int, duration: Int) throws -> String {
        let project = planner.project
        if let free = project.tracks.last(where: {
            $0.kind == "video" && $0.role == TrackRole.overlay && !$0.isLocked && !$0.isHidden
                && $0.isFree(at: frame, duration: duration)
        }) {
            return free.id
        }
        let overlay = try project.overflowTrack(from: project.requireTrack(role: TrackRole.main, kind: "video"))
        try planner.add([.addTrack(track: overlay, atIndex: project.defaultTrackIndex(kind: "video"))])
        return overlay.id
    }
}

/// `stickers list|add|import|remove`: what the Stickers panel does with image stickers.
extension ProjectDocument {
    func registerStickerCommands() {
        handle("stickers.list") { document, _, _ in
            func entry(_ url: URL) -> JSONValue {
                .object([
                    "name": .string(url.lastPathComponent), "path": .string(url.path),
                    "animated": .bool(AnimatedImageMovie.isAnimated(url)),
                ])
            }
            return .object([
                "library": .array(Self.stickerLibrary().map(entry)),
                "packs": .array(document.plugins.stickerPacks.map { pack in
                    .object([
                        "id": .string(pack.id), "plugin": .string(pack.pluginID), "title": .string(pack.title),
                        "stickers": .array(pack.stickers.map(entry)),
                    ])
                }),
            ])
        }
        handleAuthored("stickers.add") { document, arguments, author in
            guard let root = document.fileURL?.deletingLastPathComponent() else {
                throw RPCFailure(-32602, "Open a saved project first")
            }
            let url = URL(fileURLWithPath: try arguments.string("path"), relativeTo: root).standardizedFileURL
            let placed = try await document.placeSticker(
                url, at: arguments.optionalInt("atFrame"), author: author, baseRevision: try arguments.int("baseRev"))
            return .object([
                "rev": .integer(placed.revision), "media": .string(placed.mediaID), "item": .string(placed.itemID),
                "track": .string(placed.trackID),
            ])
        }
        handleAuthored("stickers.import") { document, arguments, _ in
            let url = URL(fileURLWithPath: try arguments.string("path")).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw RPCFailure(-32602, "No file at \(url.path)") }
            try document.addToStickerLibrary([url])
            return .object(["path": .string(Self.stickerLibraryFolder.appendingPathComponent(url.lastPathComponent).path)])
        }
        handleAuthored("stickers.remove") { document, arguments, _ in
            let name = try arguments.string("name")
            guard let url = Self.stickerLibrary().first(where: { $0.lastPathComponent == name }) else {
                throw RPCFailure(-32602, "No sticker named \(name) in the library")
            }
            try FileManager.default.removeItem(at: url)
            document.stickerLibraryRevision += 1
            return .object(["removed": .string(name)])
        }
    }
}

/// A sticker pack a plugin contributes (`contributes.stickers`), with the images found in its folder.
struct ContributedStickerPack: Identifiable, Equatable {
    let id: String
    let pluginID: String
    let title: String
    let stickers: [URL]
}

extension PluginManagerModel {
    /// Packs of the plugins that may run, in plugin order; a pack without images is left out.
    var stickerPacks: [ContributedStickerPack] {
        plugins.filter { availability[$0.id] == .ready }.flatMap { plugin in
            plugin.manifest.stickerPacks.compactMap { pack in
                guard let folder = plugin.stickerFolder(pack) else { return nil }
                let stickers = ProjectDocument.stickers(in: folder)
                return stickers.isEmpty ? nil : ContributedStickerPack(
                    id: pack.id, pluginID: plugin.id, title: pack.title.text, stickers: stickers)
            }
        }
    }
}
