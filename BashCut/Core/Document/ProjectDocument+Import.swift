import AVFoundation
import AppKit
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
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        busy = true
        Task {
            defer { busy = false }
            do {
                var planner = LayerPlanner(project)
                var at = project.insertionFrame(trackID: trackID, playhead: playhead)
                for url in urls {
                    let imported = try await Self.importedMedia(
                        url: url, kind: kind, projectFPS: project.fps, root: root)
                    try planner.add([.addMedia(imported.media)])
                    try planner.placeMedia(imported.media, on: trackID, at: at, duration: imported.frames)
                    at += imported.frames
                }
                try commitPlan(planner, label: "Import footage", author: .user, baseRevision: nil)
            } catch { message = error.localizedDescription }
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
        let source = url.standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        let common = zip(source, base).prefix { $0 == $1 }.count
        return (Array(repeating: "..", count: base.count - common) + source.dropFirst(common)).joined(
            separator: "/")
    }
}
