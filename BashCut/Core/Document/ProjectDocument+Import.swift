import AVFoundation
import AppKit
import BashCutProject
import UniformTypeIdentifiers

extension ProjectDocument {
    func importMedia(kind: String = "video", trackID: String = "v1") {
        guard let root = fileURL?.deletingLastPathComponent() else { return }
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
                var operations: [EditOperation] = []
                var at = insertionFrame(trackID: trackID)
                let destination = project.tracks.first(where: { $0.id == trackID })
                let dialogue = project.tracks.first(where: { $0.kind == "audio" && $0.role == "dialogue" })
                for url in urls {
                    let imported = try await Self.importedMedia(
                        url: url, kind: kind, projectFPS: project.fps, root: root)
                    operations.append(.addMedia(imported.media))
                    let videoID = UUID().uuidString
                    var item = Item(
                        id: videoID, media: imported.media.id, at: at, duration: imported.frames)
                    if destination?.kind == "video", imported.media.hasAudio == true, let dialogue {
                        let audioID = videoID + "-audio"
                        item.fields["linkedAudio"] = .string(audioID)
                        var audio = Item(
                            id: audioID, media: imported.media.id, at: at, duration: imported.frames)
                        audio.fields["linkedVideo"] = .string(videoID)
                        operations.append(.insert(track: dialogue.id, item: audio))
                    }
                    operations.append(
                        .insert(track: trackID, item: item))
                    at += imported.frames
                }
                apply(
                    .group(label: "Import footage", author: .user, ops: operations),
                    label: "Import footage")
            } catch { message = error.localizedDescription }
        }
    }

    private func insertionFrame(trackID: String) -> Int {
        trackID == "v1"
            ? project.tracks.first(where: { $0.id == trackID })?.items.map(\.end).max() ?? 0
            : playhead
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
