import AppKit
import AVFoundation
import BashCutAutomation
import BashCutDocument
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
        panel.allowedContentTypes = kind == "audio" ? [.audio] : [.movie]
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
                    let fileKind = kind ?? (UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
                        ? "audio" : "video")
                    let target = try trackID
                        ?? (fileKind == "audio" ? project.requireTrack(role: TrackRole.music) : project.requireTrack(
                            role: TrackRole.main, kind: "video")).id
                    let start = at ?? project.insertionFrame(trackID: target, playhead: playhead)
                    let imported = try await Self.importedMedia(url: url, kind: fileKind, projectFPS: project.fps, root: root)
                    DebugLog.write(
                        "import", "\(url.lastPathComponent) → \(mediaSummary(imported.media)) timelineFrames=\(imported.frames) "
                            + "target=\(target) at=\(start)")
                    try planner.add([.addMedia(imported.media)])
                    try planner.placeMedia(imported.media, on: target, at: start, duration: imported.frames)
                    mediaIDs.append(imported.media.id)
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

    /// Automation: adds one media file to the project and optionally places it like the UI import does.
    func registerImportCommands() {
        handleAuthored("media.import") { document, arguments, author in
            guard let root = document.fileURL?.deletingLastPathComponent() else {
                throw RPCFailure(-32602, "Open a saved project first")
            }
            let path = try arguments.string("path")
            let url = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw RPCFailure(-32602, "No file at \(url.path)") }
            let kind = try arguments.string("kind")
            let base = try arguments.int("baseRev")
            let imported = try await Self.importedMedia(url: url, kind: kind, projectFPS: document.project.fps, root: root)
            DebugLog.write("import", "\(url.lastPathComponent) → \(document.mediaSummary(imported.media)) (automation)")
            var planner = LayerPlanner(document.project)
            try planner.add([.addMedia(imported.media)])
            var result: [String: JSONValue] = ["media": .string(imported.media.id)]
            if arguments.bool("place") {
                let trackID = try arguments.optionalString("track")
                    ?? document.project.requireTrack(role: TrackRole.main, kind: "video").id
                let itemID = UUID().uuidString
                try planner.placeMedia(
                    imported.media, on: trackID,
                    at: arguments.optionalInt("atFrame")
                        ?? document.project.insertionFrame(trackID: trackID, playhead: document.playhead),
                    duration: imported.frames, itemID: itemID)
                result["item"] = .string(itemID)
            }
            result["rev"] = .integer(
                try document.commitPlan(planner, label: "Import media", author: author, baseRevision: base))
            document.requestProxiesAfterImport([imported.media.id], author: author)
            document.emitMediaImported([imported.media.id], author: author)
            if let item = result["item"]?.string {
                result["track"] = document.project.tracks.first { $0.items.contains { $0.id == item } }.map { .string($0.id) }
                result["linkedAudio"] = document.project.tracks.flatMap(\.items).first { $0.id == item }?
                    .fields["linkedAudio"] ?? .null
            }
            return .object(result)
        }
    }

    private static func importedMedia(
        url: URL, kind: String, projectFPS: FrameRate, root: URL
    ) async throws -> (media: Media, frames: Int) {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard kind == "audio" || video != nil else { throw ProjectError.invalid("No video track") }
        let nominal = try await video?.load(.nominalFrameRate) ?? Float(projectFPS.value)
        let fps = normalizedFrameRate(nominal)
        let duration = try await asset.load(.duration)
        let sourceFrames = Int((duration.seconds * fps.value).rounded(.down))
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
