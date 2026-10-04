import AppKit
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

    /// Asks for images and copies them into the library; a file with a name already there is kept as it is.
    func importStickers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard let urls = ModalCenter.shared.open(panel, name: "import-stickers"), !urls.isEmpty else { return }
        do {
            let folder = Self.stickerLibraryFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls {
                let destination = folder.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: url, to: destination)
                }
            }
        } catch { message = error.localizedDescription }
    }

    /// Removes a sticker from the library; projects that used it keep their own copy.
    func removeSticker(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) } catch { message = error.localizedDescription }
    }

    /// Places a library sticker at the playhead on a free overlay layer (a new one when needed), sticker sized.
    func addSticker(_ url: URL) {
        guard let root = fileURL?.deletingLastPathComponent() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
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
                let itemID = UUID().uuidString
                try planner.placeMedia(
                    media, on: stickerTrack(&planner, at: playhead, duration: duration), at: playhead,
                    duration: duration, itemID: itemID)
                try planner.add([
                    .setProperties(item: itemID, patch: ["transform": .object(["zoom": .number(Self.stickerZoom)])])
                ])
                try commitPlan(planner, label: "Add sticker", author: .user, baseRevision: nil)
                selectedID = itemID
                if existing == nil { emitMediaImported([media.id], author: .user) }
            } catch { message = error.localizedDescription }
        }
    }

    /// An unlocked, visible overlay layer that is free over the range, or a new overlay layer in front of the
    /// other video layers.
    private func stickerTrack(_ planner: inout LayerPlanner, at frame: Int, duration: Int) throws -> String {
        let project = planner.project
        if let free = project.tracks.first(where: {
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

/// A sticker pack a plugin contributes (`contributes.stickers`), with the images found in its folder.
struct ContributedStickerPack: Identifiable, Equatable {
    let id: String
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
                return stickers.isEmpty ? nil : ContributedStickerPack(id: pack.id, title: pack.title.text, stickers: stickers)
            }
        }
    }
}
