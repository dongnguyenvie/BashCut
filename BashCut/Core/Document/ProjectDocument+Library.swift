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

    /// The clip menu's and Inspector's Freeze Frame (`ui action clip.freeze`): holds the frame under the playhead, or
    /// removes the freeze when the clip already has one.
    func toggleFreezeSelected() {
        guard let item = selected else { return }
        do {
            try freezeClip(item.id, off: item.fields["freezeFrame"] != nil)
        } catch { message = error.localizedDescription }
    }

    /// Holds one source frame of a video clip for its whole length (`clip freeze`), as one undo step: the frame the
    /// clip shows at the timeline frame `atFrame` (the playhead by default), or removes the freeze with `off`.
    /// Returns the revision and the source frame held (nil when removed).
    @discardableResult
    func freezeClip(
        _ id: String? = nil, atFrame: Int? = nil, off: Bool = false, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, source: Int?) {
        guard let id = id ?? selectedID,
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
            let item = track.items.first(where: { $0.id == id })
        else { throw ProjectError.invalid("Select a video clip to freeze") }
        if off {
            guard item.fields["freezeFrame"] != nil else { throw ProjectError.invalid("\(id) has no freeze frame") }
            let revision = try commit(
                .setProperties(item: id, patch: ["freezeFrame": .null]), label: "Remove freeze frame", author: author,
                baseRevision: baseRevision)
            return (revision, nil)
        }
        guard track.kind == TrackKind.video, let media = project.media.first(where: { $0.id == item.mediaID }),
            media.kind == "video"
        else { throw ProjectError.invalid("\(id) is not a video clip; only video clips can freeze") }
        let frame = atFrame ?? playhead
        guard (item.at..<item.end).contains(frame) else {
            throw ProjectError.invalid(
                atFrame == nil
                    ? String(localized: "Move the playhead inside the selected video clip.")
                    : "Frame \(frame) is outside \(id) (\(item.at)–\(item.end - 1))")
        }
        // A frozen clip shows its held frame; freezing it again picks from its unfrozen source.
        var unfrozen = item
        unfrozen.fields["freezeFrame"] = nil
        let source = unfrozen.sourceFrame(at: frame - item.at, media: media, fps: project.fps)
        let revision = try commit(
            .setProperties(item: id, patch: ["freezeFrame": .integer(source)]), label: "Freeze frame", author: author,
            baseRevision: baseRevision)
        return (revision, source)
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
