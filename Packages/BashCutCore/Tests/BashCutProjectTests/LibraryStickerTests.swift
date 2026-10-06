import BashCutProjectFixtures
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutProject

@Suite("Sticker library (#64)")
struct LibraryStickerTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sticker-library-\(UUID().uuidString)", isDirectory: true)
    }

    /// Writes a transparent `width`×`height` image of `frames` frames (a PNG for one frame, else a GIF).
    @discardableResult
    private static func image(_ url: URL, width: Int = 40, height: Int = 20, frames: Int = 1) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let type = frames > 1 ? UTType.gif : UTType.png
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        for frame in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: Double(frame) / Double(frames), blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private static func picture(
        _ id: String = "sticker", kind: String = "image", width: Int = 400, height: Int = 200, frames: Int = 108_000
    ) -> Media {
        var fields: [String: JSONValue] = [
            "id": .string(id), "path": .string("stickers/library-abc.png"), "kind": .string(kind),
            "fps": FrameRate(30, 1).json, "frames": .integer(frames), "hasAudio": .bool(false),
            "width": .integer(width), "height": .integer(height),
        ]
        if kind == "video" {
            fields["path"] = .string("stickers/library-abc.mov")
            fields["alpha"] = .bool(true)
        }
        return Media(fields: fields)
    }

    private static func operation(_ planner: LayerPlanner) -> EditOperation {
        planner.operations.count == 1 ? planner.operations[0] : .group(label: "Place", author: .user, ops: planner.operations)
    }

    private static func item(_ params: [String: JSONValue], file: String? = nil) -> LibraryItem {
        var item = LibraryItem(id: "s", kind: .sticker, name: "S", params: params)
        if let file { item["file"] = .string(file) }
        return item
    }

    @Test("Each sticker kind checks its params and file")
    func validation() throws {
        // Emoji, as the built-in pack stores it, and the kinds read from files.
        try Self.item(["emoji": .string("🔥"), "textPreset": .string("bold-outline")]).validate()
        #expect(try LibrarySticker(params: ["emoji": .string("🔥")], file: nil).stickerKind == "emoji")
        #expect(try LibrarySticker(params: [:], file: "files/s/v1/arrow.PNG").stickerKind == "image")
        #expect(try LibrarySticker(params: [:], file: "files/s/v1/pop.mov").stickerKind == "video-alpha")
        try Self.item(["stickerKind": .string("animated")], file: "files/s/v1/dance.gif").validate()
        let full: [String: JSONValue] = [
            "stickerKind": .string("image"), "size": .number(0.25), "position": .string("top-right"),
            "animation": .string("pop-in"), "seconds": .integer(2), "width": .integer(40), "height": .integer(20),
            "license": .string("CC0"),
        ]
        let sticker = try LibrarySticker(params: full, file: "a.png")
        #expect(sticker == LibrarySticker(
            stickerKind: "image", size: 0.25, position: .named("top-right"), animation: "pop-in", seconds: 2))
        #expect(sticker.params(merging: full) == full)
        let point = try LibrarySticker(params: ["position": .object(["x": .number(0.2), "y": .number(0.7)])], file: "a.png")
        #expect(point.position == .point(x: 0.2, y: 0.7))

        let bad: [([String: JSONValue], String?, String)] = [
            (["stickerKind": .string("emoji")], nil, "params.emoji"),
            (["stickerKind": .string("image")], nil, "a file"),
            (["stickerKind": .string("video-alpha")], "files/s/v1/a.png", "cannot use a image file"),
            (["stickerKind": .string("image")], "files/s/v1/a.mov", "cannot use a video-alpha file"),
            ([:], "files/s/v1/anim.json", "Lottie"),
            ([:], "files/s/v1/anim.lottie", "Lottie"),
            ([:], "files/s/v1/notes.txt", "must be an image"),
            (["stickerKind": .string("sparkle")], "files/s/v1/a.png", "params.stickerKind"),
            (["size": .integer(2)], "files/s/v1/a.png", "params.size"),
            (["position": .string("middle")], "files/s/v1/a.png", "position"),
            (["position": .object(["x": .integer(2), "y": .integer(0)])], "files/s/v1/a.png", "position"),
            (["animation": .string("wobble")], "files/s/v1/a.png", "params.animation"),
            (["seconds": .integer(0)], "files/s/v1/a.png", "params.seconds"),
            (["emoji": .string("🔥"), "textPreset": .string("comic")], nil, "params.textPreset"),
        ]
        for (params, file, message) in bad {
            let item = Self.item(params, file: file)
            #expect(throws: ProjectError.self) { try item.validate() }
            do { try item.validate() } catch { #expect(error.localizedDescription.contains(message), "\(message)") }
        }
        #expect(throws: ProjectError.self) { try StickerPosition(text: "1.5,0.2") }
        #expect(try StickerPosition(text: " Bottom-Left ") == .named("bottom-left"))
        #expect(try StickerPosition(text: "0.25, 0.75") == .point(x: 0.25, y: 0.75))
    }

    @Test("library add reads an image's kind, size and frames: several frames make it animated")
    func imageProbe() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let still = try Self.image(folder.appendingPathComponent("arrow.png"), width: 40, height: 20)
        let params = try LibrarySticker.imageParams(["tags": .string("kept")], file: still)
        #expect(params["stickerKind"] == .string("image") && params["width"] == .integer(40) && params["height"] == .integer(20))
        #expect(params["frames"] == nil && params["tags"] == .string("kept"))
        let gif = try Self.image(folder.appendingPathComponent("dance.gif"), frames: 3)
        let animated = try LibrarySticker.imageParams([:], file: gif)
        #expect(animated["stickerKind"] == .string("animated") && animated["frames"] == .integer(3))
        #expect(throws: ProjectError.self) { try LibrarySticker.imageParams(["stickerKind": .string("video-alpha")], file: still) }
        let text = folder.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: text)
        #expect(throws: ProjectError.self) { try LibrarySticker.imageParams([:], file: text) }

        // A transparent PNG saved in the user library keeps its file and params.
        let catalog = LibraryCatalog(
            builtIn: [], user: .user(applicationSupport: folder.appendingPathComponent("support")), project: nil)
        try catalog.add(LibraryItem(id: "arrow", kind: .sticker, name: "Arrow", params: params), into: .user, file: still)
        let saved = try catalog.item("user:arrow")
        #expect(try LibrarySticker(params: saved.params, file: saved.file).stickerKind == "image")
        #expect(catalog.fileURL(of: saved).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("An image sticker goes on the Overlay layer at its size and position, as one undo step")
    func placeImage() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        #expect(project.width == 1080 && project.height == 1920)
        let sticker = LibrarySticker(stickerKind: "image")
        let placed = try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 12, size: 0.5)
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(placed.planner), label: "Add sticker")
        #expect(history.undoEntries.count == 1)
        let applied = history.project
        let track = try #require(applied.track(id: placed.trackID))
        #expect(track.role == TrackRole.overlay && track.id == "v2")
        let item = try #require(track.items.first { $0.id == placed.itemID })
        // Three seconds by default; fitted, half the frame width wide, centred.
        #expect(item.at == 12 && item.duration == 90 && item.mediaID == "sticker" && item["fill"] == .bool(false))
        #expect(item["transform"] == .object(["zoom": .number(0.5), "pan": .integer(0), "tilt": .integer(0)]))
        #expect(applied.media.contains { $0.id == "sticker" })
        try history.undo()
        var undone = history.project
        undone["rev"] = project["rev"]
        #expect(undone == project)

        // A named spot keeps the sticker inside the vertical frame's safe area; x,y is its centre.
        let corner = try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 0, position: .named("top-left"), size: 0.5)
        #expect(abs(corner.pan - -216) < 0.001 && abs(corner.tilt - 729) < 0.001)
        let point = try project.stickerPlacePlan(
            Self.picture(), sticker: sticker, at: 0, position: .point(x: 0.75, y: 0.25), size: 0.2)
        #expect(abs(point.pan - 270) < 0.001 && abs(point.tilt - 480) < 0.001 && abs(point.zoom - 0.2) < 1e-9)
        // A tall picture fits by its height, so its zoom is larger for the same width.
        let tall = try project.stickerPlacePlan(Self.picture(width: 100, height: 400), sticker: sticker, at: 0, size: 0.2)
        #expect(abs(tall.zoom - 0.45) < 1e-9)
        // The sticker's own defaults apply without options; options win over them.
        let defaults = LibrarySticker(stickerKind: "image", size: 0.1, position: .named("center"), seconds: 1)
        let byDefault = try project.stickerPlacePlan(Self.picture(), sticker: defaults, at: 0)
        #expect(abs(byDefault.zoom - 0.1) < 1e-9 && byDefault.duration == 30)
        let overridden = try project.stickerPlacePlan(Self.picture(), sticker: defaults, at: 0, duration: 45, size: 0.4)
        #expect(abs(overridden.zoom - 0.4) < 1e-9 && overridden.duration == 45)
        #expect(throws: ProjectError.self) { try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 0, size: 3) }
        #expect(throws: ProjectError.self) {
            try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 0, trackID: "a1")
        }
        #expect(throws: ProjectError.self) {
            try project.stickerPlacePlan(ProjectFixtures.media(kind: "audio"), sticker: sticker, at: 0)
        }
    }

    @Test("A missing Overlay layer is added in the same step; a busy one spills; media already there is reused")
    func overlayLayer() throws {
        var project = try ProjectFixtures.twoClips("a", "b")
        project = try project.applying(.deleteTrack(track: "v2")).project
        #expect(project.track(role: TrackRole.overlay) == nil)
        let sticker = LibrarySticker(stickerKind: "image")
        let placed = try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 0)
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(placed.planner), label: "Add sticker")
        #expect(history.undoEntries.count == 1)
        let overlay = try #require(history.project.track(role: TrackRole.overlay, kind: "video"))
        #expect(overlay.id == placed.trackID && overlay.name == "Overlay")
        // In front of the main layer, behind text.
        let order = history.project.tracks.map(\.id)
        #expect(try #require(order.firstIndex(of: overlay.id)) > (order.firstIndex(of: "v1") ?? 99))
        #expect(try #require(order.firstIndex(of: overlay.id)) < (order.firstIndex(of: "t1") ?? -1))

        let again = try history.project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 30)
        #expect(again.trackID != overlay.id)
        let twice = try history.project.applying(Self.operation(again.planner)).project
        #expect(twice.media.filter { $0.id == "sticker" }.count == 1)
        #expect(twice.tracks.filter { $0.role == TrackRole.overlay }.count == 2)
    }

    @Test("A video sticker plays once, at most its length; an animation moves around the sticker's framing")
    func videoAndAnimation() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let movie = Self.picture("pop", kind: "video", frames: 45)
        let placed = try project.stickerPlacePlan(movie, sticker: LibrarySticker(stickerKind: "video-alpha"), at: 0, duration: 100)
        #expect(placed.duration == 45 && placed.shortened)
        let whole = try project.stickerPlacePlan(movie, sticker: LibrarySticker(stickerKind: "video-alpha"), at: 0)
        #expect(whole.duration == 45 && !whole.shortened)

        let animated = LibrarySticker(stickerKind: "image", size: 0.5, position: .point(x: 0.75, y: 0.5), animation: "pop-in")
        let plan = try project.stickerPlacePlan(Self.picture(), sticker: animated, at: 0)
        let applied = try project.applying(Self.operation(plan.planner)).project
        let item = try #require(applied.tracks.flatMap(\.items).first { $0.id == plan.itemID })
        let motion = try #require(item.motion)
        // Pop-in's zoom keys (0.6 → 1.08 → 1) scale the sticker's own zoom of 0.5.
        #expect(motion.keys["zoom"]?.map(\.value) == [0.3, 0.54, 0.5])
        let slide = LibrarySticker(stickerKind: "image", size: 0.5, position: .point(x: 0.5, y: 0.25), animation: "slide-up")
        let slid = try project.stickerPlacePlan(Self.picture(), sticker: slide, at: 0)
        let slidItem = try #require(try project.applying(Self.operation(slid.planner)).project.tracks.flatMap(\.items)
            .first { $0.id == slid.itemID })
        #expect(slidItem.motion?.keys["tilt"]?.last?.value == 480)
    }

    @Test("Placed stickers are copied into stickers/ once per content, and project library files are copied too")
    func projectCopies() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("project", isDirectory: true)
        let outside = try Self.image(folder.appendingPathComponent("outside/arrow.png"))
        let same = folder.appendingPathComponent("outside/arrow-copy.PNG")
        try FileManager.default.copyItem(at: outside, to: same)
        let copy = try LibraryStore.projectCopy(of: outside, root: root, folder: LibrarySticker.projectFolder)
        #expect(copy.deletingLastPathComponent().lastPathComponent == "stickers" && copy.lastPathComponent.hasPrefix("library-"))
        #expect(try LibraryStore.projectCopy(of: same, root: root, folder: "stickers") == copy)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("stickers").path).count == 1)
        // Project media already in the folder is used where it is.
        #expect(try LibraryStore.projectCopy(of: copy, root: root, folder: "stickers") == copy)

        // A project-scope item's file lives in .bashcut/library; placing it still copies it, so removing the item
        // never breaks the timeline. The same holds for audio (#78).
        let catalog = LibraryCatalog(builtIn: [], user: nil, project: .project(root: root))
        try catalog.add(
            LibraryItem(id: "arrow", kind: .sticker, name: "Arrow", params: ["stickerKind": .string("image")]),
            into: .project, file: outside)
        let item = try catalog.item("project:arrow")
        let libraryFile = try #require(catalog.fileURL(of: item))
        #expect(libraryFile.path.contains("/.bashcut/library/"))
        let placedCopy = try LibraryStore.projectCopy(of: libraryFile, root: root, folder: "stickers")
        #expect(placedCopy == copy)
        let sound = try LibraryAudio.projectCopy(of: libraryFile, root: root, folder: "sfx")
        #expect(sound != libraryFile && sound.deletingLastPathComponent().lastPathComponent == "sfx")

        // Removing the sticker while the timeline uses it leaves the project copy alone.
        let store = try catalog.store(.project)
        let removed = try store.remove("arrow", keeping: [copy])
        #expect(removed.kept.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: libraryFile.path))
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test("Removing an item keeps the files project media still points at directly")
    func removeKeepsUsedFiles() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("project", isDirectory: true)
        let file = try Self.image(folder.appendingPathComponent("star.png"))
        let catalog = LibraryCatalog(builtIn: [], user: nil, project: .project(root: root))
        let store = try catalog.store(.project)
        try catalog.add(LibraryItem(id: "star", kind: .sticker, name: "Star"), into: .project, file: file)
        let used = try #require(catalog.fileURL(of: try catalog.item("star")))
        let result = try store.remove("star", keeping: [used, file])
        #expect(result.item.id == "star")
        #expect(result.kept == ["files/star/v1/star.png"])
        #expect(FileManager.default.fileExists(atPath: used.path))
        #expect(try store.items().isEmpty)
    }

    @Test("Save selection as sticker round-trips an image's size and position, and an emoji's text")
    func saveSelectionRoundTrip() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let sticker = LibrarySticker(stickerKind: "image", size: 0.25, position: .point(x: 0.2, y: 0.7), seconds: 2)
        let plan = try project.stickerPlacePlan(Self.picture(), sticker: sticker, at: 0)
        let applied = try project.applying(Self.operation(plan.planner)).project
        let item = try #require(applied.tracks.flatMap(\.items).first { $0.id == plan.itemID })
        let media = try #require(applied.media.first { $0.id == "sticker" })
        let params = try LibrarySelection.sticker(item, media: media, project: applied)
        let saved = try LibrarySticker(params: params, file: "a.png")
        #expect(saved == sticker)
        #expect(params["width"] == .integer(400) && params["height"] == .integer(200))
        // Placing the saved sticker again gives the same framing.
        let again = try applied.stickerPlacePlan(media, sticker: saved, at: 100)
        #expect(abs(again.zoom - plan.zoom) < 1e-6 && abs(again.pan - plan.pan) < 0.01 && abs(again.tilt - plan.tilt) < 0.01)
        #expect(try LibrarySelection.sticker(item, media: media, project: applied, frames: 4)["stickerKind"] == .string("animated"))
        let movie = Self.picture("pop", kind: "video", frames: 45)
        #expect(try LibrarySelection.sticker(item, media: movie, project: applied)["stickerKind"] == .string("video-alpha"))
        var opaque = movie
        opaque["alpha"] = nil
        #expect(throws: ProjectError.self) { try LibrarySelection.sticker(item, media: opaque, project: applied) }

        var text = Item(at: 0, duration: 30)
        text["text"] = .string(" 🔥 ")
        text["textPreset"] = .string("keyword-sticker")
        let emoji = try LibrarySelection.params(.sticker, item: text)
        #expect(emoji == ["stickerKind": .string("emoji"), "emoji": .string("🔥"), "textPreset": .string("keyword-sticker")])
        try LibraryItem(id: "fire2", kind: .sticker, name: "Fire", params: emoji).validate()
        text["text"] = .string(String(repeating: "long caption ", count: 5))
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.sticker, item: text) }
        #expect(LibrarySelection.kinds.contains(.sticker))
    }

    @Test("Built-in emoji stickers are unchanged")
    func builtInEmoji() throws {
        #expect(LibraryBuiltIns.stickers.count == 8)
        for item in LibraryBuiltIns.stickers {
            try item.validate()
            let sticker = try LibrarySticker(params: item.params, file: item.file)
            #expect(sticker.stickerKind == "emoji" && !sticker.isMedia)
            #expect(item.params["textPreset"] == .string("bold-outline") && item.params["stickerKind"] == nil)
        }
    }
}
