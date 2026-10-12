import AppKit
import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import UniformTypeIdentifiers

extension ProjectDocument {
    /// Imports files onto `trackID`, or onto the main video track when nil.
    func importMedia(kind: String = "video", trackID: String? = nil) {
        guard let root = fileURL?.deletingLastPathComponent() else { return }
        guard let trackID = trackID ?? project.track(role: TrackRole.main, kind: "video")?.id else {
            message = String(localized: "Add a main video track first")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = kind == "audio" ? [.audio] : [.movie, .image]
        panel.allowsMultipleSelection = true
        panel.directoryURL = root.appendingPathComponent("footage")
        guard let urls = ModalCenter.shared.open(panel, name: "import-media"), !urls.isEmpty else { return }
        importFiles(urls, kind: kind, trackID: trackID, at: nil)
    }

    /// Imports files and places them one after another on `trackID` (the main video layer, or Music for audio,
    /// when nil) from `frame` (the usual insertion point when nil). Used by Import and by dropping files on the
    /// timeline; the kind comes from each file's type unless given.
    func importFiles(_ urls: [URL], kind: String? = nil, trackID: String?, at frame: Int?) {
        guard let root = fileURL?.deletingLastPathComponent(), !urls.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                var planner = LayerPlanner(project)
                var at = frame
                var mediaIDs: [String] = []
                for url in urls {
                    let fileKind = kind == "video" && StillImageMovie.isImage(url) ? "image" : kind ?? Self.kind(of: url)
                    let target = try trackID ?? defaultTrackID(forKind: fileKind)
                    let start = at ?? project.insertionFrame(trackID: target, playhead: playhead)
                    var imported = try await Self.importedMedia(url: url, kind: fileKind, projectFPS: project.fps, root: root)
                    let existing = planner.project.existingMedia(like: imported.media)
                    DebugLog.write(
                        "import", "\(url.lastPathComponent) → \(mediaSummary(imported.media)) timelineFrames=\(imported.frames) "
                            + "target=\(target) at=\(start)" + (existing.map { " reusing \($0.id)" } ?? ""))
                    if let existing {
                        imported.media = existing
                    } else {
                        try planner.add([.addMedia(imported.media)])
                        mediaIDs.append(imported.media.id)
                    }
                    try planner.placeMedia(imported.media, on: target, at: start, duration: imported.frames)
                    at = start + imported.frames
                }
                try commitPlan(planner, label: "Import footage", author: .user, baseRevision: nil)
                requestProxiesAfterImport(mediaIDs, author: .user)
                emitMediaImported(mediaIDs, author: .user)
                let linked = project.tracks.flatMap(\.items).filter { $0.fields["linkedAudio"] != nil }.count
                DebugLog.write("import", "done; items with linked audio=\(linked) layers: \(layoutSummary())")
            } catch {
                DebugLog.write("import", "FAILED: \(error.localizedDescription)")
                message = error.localizedDescription
            }
        }
    }

    /// Files dropped on the Media panel (#408): added to the project like `media import` without `--place` (media
    /// already in the project is reused), as one undoable edit.
    func importFilesToMedia(_ urls: [URL]) {
        guard let root = fileURL?.deletingLastPathComponent(), !urls.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                var planner = LayerPlanner(project)
                var mediaIDs: [String] = []
                for url in urls {
                    let imported = try await Self.importedMedia(url: url, kind: Self.kind(of: url), projectFPS: project.fps, root: root)
                    guard planner.project.existingMedia(like: imported.media) == nil else { continue }
                    try planner.add([.addMedia(imported.media)])
                    mediaIDs.append(imported.media.id)
                }
                guard !mediaIDs.isEmpty else { return }
                try commitPlan(planner, label: "Import media", author: .user, baseRevision: nil)
                requestProxiesAfterImport(mediaIDs, author: .user)
                emitMediaImported(mediaIDs, author: .user)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Automation: adds one media file to the project and optionally places it like the UI import does.
    func registerImportCommands() {
        handleAuthored("media.import") { document, arguments, author in
            guard let root = document.fileURL?.deletingLastPathComponent() else {
                throw RPCFailure(-32602, "Open a saved project first")
            }
            let path = try arguments.string("path")
            let url = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
            if try Self.isFolder(url) { return try await document.importFolder(url, root: root, arguments: arguments, author: author) }
            let kind = arguments.optionalString("kind") ?? Self.kind(of: url)
            let base = try arguments.int("baseRev")
            var imported = try await Self.importedMedia(url: url, kind: kind, projectFPS: document.project.fps, root: root)
            let existing = document.project.existingMedia(like: imported.media)
            DebugLog.write(
                "import", "\(url.lastPathComponent) → \(document.mediaSummary(imported.media)) (automation)"
                    + (existing.map { " reusing \($0.id)" } ?? ""))
            var planner = LayerPlanner(document.project)
            let (license, provenance) = Self.mediaRights(arguments)
            if let existing {
                imported.media = existing
                // Rights given again for media already here are recorded on it (P2-H8).
                if license != nil || provenance != nil {
                    try planner.add([.setMediaRights(media: existing.id, license: license, provenance: provenance)])
                }
            } else {
                if let license { imported.media.fields["license"] = license }
                if let provenance { imported.media.fields["provenance"] = provenance }
                try planner.add([.addMedia(imported.media)])
            }
            var result: [String: JSONValue] = ["media": .string(imported.media.id), "existing": .bool(existing != nil)]
            if arguments.bool("place") {
                let trackID = try arguments.optionalString("track")
                    ?? document.defaultTrackID(forKind: imported.media.kind)
                let itemID = UUID().uuidString
                try planner.placeMedia(
                    imported.media, on: trackID,
                    at: arguments.optionalInt("atFrame")
                        ?? document.project.insertionFrame(trackID: trackID, playhead: document.playhead),
                    duration: imported.frames, itemID: itemID)
                result["item"] = .string(itemID)
            }
            // Reusing media without placing it is an empty plan: it keeps the revision (#347).
            result["rev"] = .integer(
                try document.commitPlan(planner, label: "Import media", author: author, baseRevision: base))
            // Waits for the probe only: an agent sees `converting` (with the job to wait for) when this Mac cannot
            // decode the video, also when importing such media again.
            if let proxy = try? await document.requestProxies(mediaIDs: [imported.media.id], author: author).first {
                result["proxy"] = proxy
            }
            if existing == nil { document.emitMediaImported([imported.media.id], author: author) }
            if let item = result["item"]?.string {
                result["track"] = document.project.tracks.first { $0.items.contains { $0.id == item } }.map { .string($0.id) }
                result["linkedAudio"] = document.project.tracks.flatMap(\.items).first { $0.id == item }?
                    .fields["linkedAudio"] ?? .null
            }
            return .object(result)
        }
    }

    /// Whether `url` is a folder; throws when nothing is there.
    static func isFolder(_ url: URL) throws -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw RPCFailure(-32602, "No file at \(url.path)")
        }
        return isFolder.boolValue
    }

    /// `media.import` of a folder: every video, audio and image file directly inside it, in name order, as one edit
    /// (files already in the project are reused); nothing is placed.
    func importFolder(
        _ folder: URL, root: URL, arguments: CommandArguments, author: Author, only: [URL]? = nil
    ) async throws -> JSONValue {
        guard !arguments.bool("place") else { throw RPCFailure(-32602, "place takes one file; import the folder, then place") }
        let files = try only ?? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                let type = UTType(filenameExtension: url.pathExtension)
            else { return false }
            return type.conforms(to: .audiovisualContent) || type.conforms(to: .image)
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !files.isEmpty else { throw RPCFailure(-32602, "No video, audio or image files in \(folder.path)") }
        let (license, provenance) = Self.mediaRights(arguments)
        let forcedKind = arguments.optionalString("kind")
        var planner = LayerPlanner(project)
        var rows: [JSONValue] = []
        var added: [String] = []
        for url in files {
            let kind = forcedKind ?? Self.kind(of: url)
            var imported: (media: Media, frames: Int)
            do {
                let result = try await Self.importedMedia(url: url, kind: kind, projectFPS: project.fps, root: root)
                imported = (result.media, result.frames)
            } catch {
                rows.append(.object(["path": .string(url.lastPathComponent), "error": .string(error.localizedDescription)]))
                continue
            }
            let existing = planner.project.existingMedia(like: imported.media)
            if let existing {
                imported.media = existing
                if license != nil || provenance != nil {
                    try planner.add([.setMediaRights(media: existing.id, license: license, provenance: provenance)])
                }
            } else {
                if let license { imported.media.fields["license"] = license }
                if let provenance { imported.media.fields["provenance"] = provenance }
                try planner.add([.addMedia(imported.media)])
                added.append(imported.media.id)
            }
            rows.append(.object([
                "path": .string(url.lastPathComponent), "media": .string(imported.media.id), "kind": .string(imported.media.kind),
                "seconds": .number((imported.media.durationSeconds * 100).rounded() / 100), "existing": .bool(existing != nil),
            ]))
        }
        DebugLog.write("import", "folder \(folder.lastPathComponent): \(files.count) files, \(added.count) new (automation)")
        let revision = try commitPlan(planner, label: "Import folder", author: author, baseRevision: try arguments.int("baseRev"))
        let proxies = added.isEmpty ? [] : (try? await requestProxies(mediaIDs: added, author: author)) ?? []
        if !added.isEmpty { emitMediaImported(added, author: author) }
        return .object([
            "rev": .integer(revision), "files": .array(rows), "added": .integer(added.count),
            "converting": .array(proxies.filter { $0.object["status"]?.string == "converting" }),
        ])
    }

    /// `license` (text, or a JSON object) and `provenance` from `media import`'s rights options; nil when not given.
    static func mediaRights(_ arguments: CommandArguments) -> (license: JSONValue?, provenance: JSONValue?) {
        let license = arguments.optionalString("license").map { LicenseTerms.argument($0) }
        let provenance = Provenance.from(
            origin: arguments.optionalString("origin"), sourceUrl: arguments.optionalString("source"),
            author: arguments.optionalString("author"))
        return (license, provenance)
    }

    /// The media kind a file's type suggests: audio, image or video.
    static func kind(of url: URL) -> String {
        if StillImageMovie.isImage(url) { return "image" }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true ? "audio" : "video"
    }

    /// An image: its oriented size, the project frame rate and `Media.imageMaximumSeconds` of frames, placed for
    /// `Media.imageDefaultSeconds`.
    static func importedImage(url: URL, projectFPS: FrameRate, root: URL) throws -> (media: Media, frames: Int) {
        guard let size = StillImageMovie.pixelSize(of: url) else {
            throw ProjectError.invalid("Cannot read the image \(url.lastPathComponent)")
        }
        let fields: [String: JSONValue] = [
            "id": .string(UUID().uuidString), "path": .string(relativePath(url, root: root)), "kind": .string("image"),
            "fps": projectFPS.json, "frames": .integer(Int(Media.imageMaximumSeconds * projectFPS.value)),
            "hasAudio": .bool(false), "width": .integer(Int(size.width)), "height": .integer(Int(size.height)),
        ]
        let media = Media(fields: fields)
        return (media, media.placementFrames(in: projectFPS))
    }

    static func importedMedia(
        url: URL, kind: String, projectFPS: FrameRate, root: URL
    ) async throws -> (media: Media, frames: Int) {
        if kind == "image" { return try importedImage(url: url, projectFPS: projectFPS, root: root) }
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard kind == "audio" || video != nil else { throw ProjectError.invalid("No video track") }
        let nominal = try await video?.load(.nominalFrameRate) ?? Float(projectFPS.value)
        let fps = normalizedFrameRate(nominal)
        let sourceFrames = try await MediaFrames.sourceFrames(of: asset, fps: fps)
        let frames = Int((Double(sourceFrames) / fps.value * projectFPS.value).rounded(.down))
        guard frames > 0 else { throw ProjectError.invalid("Video is too short") }
        let id = UUID().uuidString
        var fields: [String: JSONValue] = [
            "id": .string(id), "path": .string(relativePath(url, root: root)),
            "kind": .string(kind), "fps": fps.json, "frames": .integer(sourceFrames),
            "hasAudio": .bool(!audio.isEmpty),
        ]
        if let video {
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let transformed = size.applying(transform)
            fields["width"] = .integer(Int(abs(transformed.width).rounded()))
            fields["height"] = .integer(Int(abs(transformed.height).rounded()))
            // A movie with an alpha channel (a rendered graphic) is shown with its transparency, like a video sticker.
            if (try? await video.load(.formatDescriptions))?.contains(where: hasAlpha) == true { fields["alpha"] = .bool(true) }
        }
        return (Media(fields: fields), frames)
    }

    private static func normalizedFrameRate(_ nominal: Float) -> FrameRate {
        if abs(nominal - 29.97) < 0.02 { return FrameRate() }
        if abs(nominal - 59.94) < 0.02 { return FrameRate(60000, 1001) }
        if abs(nominal - 23.976) < 0.02 { return FrameRate(24000, 1001) }
        return FrameRate(max(1, Int(nominal.rounded())), 1)
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        MediaPathResolver.projectPath(for: url, projectRoot: root)
    }
}
