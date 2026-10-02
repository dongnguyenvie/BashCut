import AVFoundation
import BashCutProject
import Foundation

extension ProjectDocument {
    func previewSource(_ media: Media) {
        guard let url = resolvedMediaURL(media) else {
            message = String(localized: "Shared media requires a configured workspace.")
            return
        }
        player.pause()
        sourceViewer.open(media, url: url)
    }
    func resolvedMediaURL(_ media: Media) -> URL? {
        guard let root = fileURL?.deletingLastPathComponent() else { return nil }
        return try? MediaPathResolver.resolve(
            media.path, projectRoot: root, workspaceRoot: agents.workspace)
    }
    func placeSource(_ mode: PlacementMode) {
        guard let media = sourceViewer.media else { return }
        do {
            let operation = try project.sourceEdit(
                mediaID: media.id, sourceRange: sourceViewer.inFrame..<sourceViewer.outFrame, at: playhead,
                trackID: "v1", mode: mode)
            apply(operation, label: mode == .insert ? "Insert source range" : "Overwrite source range")
            sourceViewer.close()
        } catch { message = error.localizedDescription }
    }
    func patchSelected(_ patch: [String: JSONValue], label: String) {
        guard let selectedID else { return }
        apply(.setProperties(item: selectedID, patch: patch), label: label)
    }
    func patchSelectedTrack(_ patch: [String: JSONValue], label: String) {
        guard let track = selectedItemTrack else { return }
        apply(.setTrackProperties(track: track.id, patch: patch), label: label)
    }
    func addText(style: String, text: String = "Your caption") {
        var item = Item(at: playhead, duration: max(1, min(90, project.duration - playhead)))
        item["text"] = .string(text)
        item["style"] = .string(style)
        apply(.insert(track: "t1", item: item), label: "Add text")
        selectedID = item.id
    }
    func appendMedia(_ media: Media, track: String = "v1") {
        let duration = Int((Double(media.frames) / media.fps.value * project.fps.value).rounded(.down))
        let at =
            track == "v1"
            ? project.tracks.first { $0.id == track }?.items.map(\.end).max() ?? 0 : playhead
        let itemID = UUID().uuidString
        var item = Item(id: itemID, media: media.id, at: at, duration: duration)
        var operations: [EditOperation] = []
        if project.tracks.first(where: { $0.id == track })?.kind == "video", media.hasAudio == true,
            let dialogue = project.tracks.first(where: { $0.kind == "audio" && $0.role == "dialogue" })
        {
            let audioID = itemID + "-audio"
            item.fields["linkedAudio"] = .string(audioID)
            var audio = Item(id: audioID, media: media.id, at: at, duration: duration)
            audio.fields["linkedVideo"] = .string(itemID)
            operations.append(.insert(track: dialogue.id, item: audio))
        }
        operations.append(.insert(track: track, item: item))
        apply(.group(label: "Insert media", author: .user, ops: operations), label: "Insert media")
        selectedID = item.id
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
        let elapsed = Double(playhead - item.at) / project.fps.value
        let source = item.sourceIn + Int((elapsed * media.fps.value * item.speed).rounded(.down))
        apply(
            .setProperties(item: item.id, patch: ["freezeFrame": .integer(source)]),
            label: "Freeze frame")
    }

    func addGeneratedVoice(_ asset: GeneratedPluginAsset) async throws {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before generating voiceover")
        }
        let mediaAsset = AVURLAsset(url: asset.url)
        let duration = try await mediaAsset.load(.duration)
        let frames = Int((duration.seconds * project.fps.value).rounded(.down))
        guard frames > 0, try await !mediaAsset.loadTracks(withMediaType: .audio).isEmpty else {
            throw ProjectError.invalid("Voice plugin output is not a valid audio file")
        }
        let id = UUID().uuidString
        let media = Media(fields: [
            "id": .string(id), "path": .string(Self.relativePath(asset.url, root: root)),
            "kind": .string("audio"), "fps": project.fps.json, "frames": .integer(frames),
            "generatedBy": .object([
                "plugin": .string(asset.pluginID), "provider": .string(asset.providerID),
                "version": .string(asset.pluginVersion),
            ]),
        ])
        let item = Item(media: id, at: playhead, duration: frames)
        apply(
            .group(
                label: "Generate voiceover", author: .user,
                ops: [.addMedia(media), .insert(track: "a2", item: item)]),
            label: "Generate voiceover")
        selectedID = item.id
        selectedTrackID = "a2"
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
        apply(
            .group(
                label: "Record voiceover", author: .user,
                ops: [.addMedia(media), .insert(track: "a2", item: item)]),
            label: "Record voiceover")
        selectedID = item.id
        selectedTrackID = "a2"
    }

    func applyBeatGrid(_ generated: GeneratedBeatGrid, media: Media) throws {
        var frames = Set<Int>()
        for item in project.tracks.flatMap(\.items) where item.mediaID == media.id {
            let sourceStart = Double(item.sourceIn) / media.fps.value
            let sourceDuration = Double(item.duration) / project.fps.value * item.speed
            let sourceEnd = sourceStart + sourceDuration
            for second in generated.beatSeconds where second >= sourceStart && second <= sourceEnd {
                let offset = (second - sourceStart) / item.speed * project.fps.value
                let frame = item.at + Int(offset.rounded())
                if frame >= item.at && frame <= item.end { frames.insert(frame) }
            }
        }
        guard !frames.isEmpty else {
            throw ProjectError.invalid("Insert the selected audio into the timeline before detecting beats")
        }
        apply(
            .setBeatGrid(
                media: media.id, bpm: generated.bpm, frames: frames.sorted(),
                provenance: [
                    "plugin": .string(generated.pluginID), "provider": .string(generated.providerID),
                    "version": .string(generated.pluginVersion),
                ]),
            label: "Detect beats")
    }
}
