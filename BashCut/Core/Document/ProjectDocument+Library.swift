import AVFoundation
import BashCutAutomation
import BashCutProject
import Foundation

extension ProjectDocument {
    func previewSource(_ media: Media) {
        guard let url = resolvedMediaURL(media) else {
            message = String(localized: "Shared media requires a configured workspace.")
            return
        }
        guard !media.isImage else {
            message = String(localized: "Images have no source preview; drag them onto the timeline.")
            return
        }
        preview.pause()
        sourceViewer.open(media, url: url)
    }
    /// Working on the timeline (a click, a drag, a seek or a selection) shows the timeline again, so the viewer never
    /// keeps showing a Media clip while the timeline is being edited.
    func showTimelineViewer() {
        guard sourceViewer.visible else { return }
        sourceViewer.close()
        DebugLog.write("ui", "viewer back to the timeline")
    }
    func resolvedMediaURL(_ media: Media) -> URL? {
        guard let root = fileURL?.deletingLastPathComponent() else { return nil }
        return try? MediaPathResolver.resolve(
            media.path, projectRoot: root, workspaceRoot: settings.workspace)
    }
    func placeSource(_ mode: PlacementMode, author: Author = .user) throws {
        guard let media = sourceViewer.media else { throw ProjectError.invalid("Open a clip in the source viewer") }
        let operation = try project.sourceEdit(
            mediaID: media.id, sourceRange: sourceViewer.inFrame..<sourceViewer.outFrame, at: playhead,
            trackID: project.requireTrack(role: TrackRole.main, kind: "video").id, mode: mode)
        try commit(
            operation, label: mode == .insert ? "Insert source range" : "Overwrite source range", author: author)
        sourceViewer.close()
    }
    /// `coalescing` merges continuous input (slider drags, typing) on the same keys into one undo step.
    func patchSelected(_ patch: [String: JSONValue], label: String, coalescing: Bool = false) {
        guard let selectedID else { return }
        applyCoalescing(
            .setProperties(item: selectedID, patch: patch), label: label,
            key: coalescing ? "item:\(selectedID):" + patch.keys.sorted().joined(separator: ",") : nil)
    }
    func patchSelectedTrack(_ patch: [String: JSONValue], label: String, coalescing: Bool = false) {
        guard let track = selectedItemTrack else { return }
        applyCoalescing(
            .setTrackProperties(track: track.id, patch: patch), label: label,
            key: coalescing ? "track:\(track.id):" + patch.keys.sorted().joined(separator: ",") : nil)
    }

    private func applyCoalescing(_ operation: EditOperation, label: String, key: String?) {
        do { try commit(operation, label: label, coalescingKey: key) } catch { message = error.localizedDescription }
    }
    /// Places media on `track`, or on the main video track when nil.
    func appendMedia(_ media: Media, track: String? = nil) {
        let itemID = UUID().uuidString
        do {
            try placeMedia(media, trackID: track, itemID: itemID)
            selectedID = itemID
        } catch { message = error.localizedDescription }
    }

    func unlinkSelectedAudio() {
        guard let item = selected, let linked = item.linkedItemID else { return }
        let videoID = item.fields["linkedAudio"] == nil ? linked : item.id
        apply(.setLinkedAudio(video: videoID, audio: nil), label: "Unlink audio")
    }

    func toggleFreezeSelected() {
        guard let item = selected else { return }
        if item.fields["freezeFrame"] != nil {
            apply(.setProperties(item: item.id, patch: ["freezeFrame": .null]), label: "Remove freeze frame")
            return
        }
        guard let media = project.media.first(where: { $0.id == item.mediaID }),
            (item.at..<item.end).contains(playhead)
        else {
            message = String(localized: "Move the playhead inside the selected video clip.")
            return
        }
        let elapsed = item.sourceSeconds(afterFrames: playhead - item.at, fps: project.fps)
        let source = item.sourceIn + Int((elapsed * media.fps.value).rounded(.down))
        apply(
            .setProperties(item: item.id, patch: ["freezeFrame": .integer(source)]),
            label: "Freeze frame")
    }

    func addRecordedVoice(_ url: URL) async throws {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before recording voiceover")
        }
        let allowed = root.appendingPathComponent("voiceover", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(allowed.path + "/") else {
            throw ProjectError.invalid("Recorded voiceover must stay in the project voiceover folder")
        }
        let asset = AVURLAsset(url: resolved)
        let duration = try await asset.load(.duration)
        let frames = Int((duration.seconds * project.fps.value).rounded(.down))
        guard frames > 0, try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw ProjectError.invalid("Recording is too short or has no audio")
        }
        let mediaID = UUID().uuidString
        let media = Media(fields: [
            "id": .string(mediaID), "path": .string(Self.relativePath(resolved, root: root)),
            "kind": .string("audio"), "fps": project.fps.json, "frames": .integer(frames),
            "hasAudio": .bool(true),
            "recordedBy": .object([
                "source": .string("microphone"), "sampleRate": .integer(48_000),
            ]),
        ])
        let item = Item(media: mediaID, at: playhead, duration: frames)
        let track = try project.requireTrack(role: TrackRole.voiceover, kind: "audio")
        try commit(
            .group(
                label: "Record voiceover", author: .user,
                ops: [.addMedia(media), .insert(track: track.id, item: item)]),
            label: "Record voiceover")
        selectedID = item.id
        selectedTrackID = track.id
    }
}
