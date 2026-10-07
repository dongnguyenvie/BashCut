import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Plays library sounds in the Audio panel (#78), one at a time. `library preview` drives the same player.
@MainActor @Observable
final class LibraryAudioPreview {
    static let shared = LibraryAudioPreview()

    /// The item playing (`scope:id`), if any.
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ending: Task<Void, Never>?

    /// Plays `url` from its start, stopping any other sound. Returns its length in seconds.
    @discardableResult
    func play(_ url: URL, reference: String) throws -> Double {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.play() else { throw RPCFailure(-32602, "\(url.lastPathComponent) cannot be played") }
        self.player = player
        playing = reference
        let seconds = player.duration
        ending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.2))
            guard !Task.isCancelled, let self, self.player === player, !player.isPlaying else { return }
            self.stop()
        }
        return seconds
    }

    func stop() {
        ending?.cancel()
        ending = nil
        player?.stop()
        player = nil
        playing = nil
    }
}

/// The audio library (#78): music, sound effects and ambience saved with a role, length, tempo, loudness and loop
/// flag. Placing one copies its file into the project (once per content) and puts it on the Music or SFX layer;
/// analyzing one measures it with the same providers `audio measure` and `beats detect` use.
extension ProjectDocument {
    // MARK: Project media

    /// Project media for the sound file of the library item `source` (an audio item, or a preset with its own
    /// sound). A file from outside the project is copied into `folder` (`sfx` or `music`) first, named by its content
    /// so the same sound is copied once, and a file already in use reuses its media.
    func librarySoundMedia(_ source: LibraryItem, folder: String = "sfx") async throws -> Media {
        let catalog = libraryCatalog
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before adding a sound from the library")
        }
        guard let file = catalog.fileURL(of: source) else { throw RPCFailure(-32602, "\(source.reference) has no file") }
        let digest = source.scope.isWritable ? source["fileSHA256"]?.string : nil
        let url = try await LibraryWorker.shared.run {
            try LibraryAudio.projectCopy(of: file, root: root, folder: folder, sha256: digest)
        }
        let seconds = try await Self.soundSeconds(url, label: source.reference)
        let frames = Int((seconds * project.fps.value).rounded(.down))
        guard frames > 0 else { throw RPCFailure(-32602, "\(source.reference) is too short") }
        var fields: [String: JSONValue] = [
            "id": .string(UUID().uuidString), "path": .string(Self.relativePath(url, root: root)),
            "kind": .string("audio"), "fps": project.fps.json, "frames": .integer(frames), "hasAudio": .bool(true),
        ]
        if source.kind == .audio { fields[TransitionPreset.soundLibraryField] = .string(source.reference) }
        let media = Media(fields: fields)
        return project.existingMedia(like: media) ?? media
    }

    /// The length of a sound file in seconds; throws when it has no sound.
    nonisolated static func soundSeconds(_ url: URL, label: String) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw RPCFailure(-32602, "\(label) is not a sound file BashCut can read")
        }
        guard !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
            throw RPCFailure(-32602, "\(label) is too short or has no sound")
        }
        return duration.seconds
    }

    private func libraryAudio(_ item: LibraryItem) throws -> LibraryAudio {
        guard item.kind == .audio else { throw RPCFailure(-32602, "\(item.reference) is not an audio library item") }
        do { return try LibraryAudio(params: item.params, label: item.reference) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
    }

    /// A new audio item's params: its length measured from `file` and, without a role, one from that length.
    func audioItemParams(_ params: [String: JSONValue], file: URL) async throws -> [String: JSONValue] {
        var audio: LibraryAudio
        do { audio = try LibraryAudio(params: params) } catch { throw RPCFailure(-32602, error.localizedDescription) }
        let seconds = try await Self.soundSeconds(file, label: file.lastPathComponent)
        audio.seconds = audio.seconds ?? seconds
        audio.role = audio.placementRole(seconds: seconds)
        return audio.params(merging: params)
    }

    // MARK: Placing

    /// Places an audio item at the playhead (or `placement.frame`) as one undo step: its file copied into the
    /// project's `music` or `sfx` folder, its media and the clip, on the Music layer (music, ambience) or SFX layer
    /// (sfx), added when missing. A loopable sound repeats to fill a longer `duration`; another plays once.
    func placeLibraryAudio(_ item: LibraryItem, _ placement: LibraryPlacement) async throws -> (revision: Int, AudioPlacement) {
        let audio = try libraryAudio(item)
        var seconds = audio.seconds
        if audio.role == nil, seconds == nil, let file = libraryCatalog.fileURL(of: item) {
            seconds = try await Self.soundSeconds(file, label: item.reference)
        }
        let role = audio.placementRole(seconds: seconds)
        let sound = try await librarySoundMedia(item, folder: LibraryAudio.projectFolder(role))
        let placed: AudioPlacement
        do {
            placed = try project.audioPlacePlan(
                sound, role: role, loopable: audio.loopable == true, at: placement.frame ?? playhead,
                duration: placement.duration, trackID: placement.trackID)
        } catch { throw RPCFailure(-32602, error.localizedDescription) }
        let revision = try commitPlan(
            placed.planner, label: item.name, author: placement.author, baseRevision: placement.baseRevision)
        selectedTrackID = placed.trackID
        selectedID = placed.itemIDs.first
        recordLibraryUse(item)
        return (revision, placed)
    }

    /// `library place` for an audio item: what was placed, and whether it looped or plays shorter than asked.
    func placeLibraryAudioCommand(_ item: LibraryItem, _ placement: LibraryPlacement) async throws -> JSONValue {
        let (revision, placed) = try await placeLibraryAudio(item, placement)
        var result: [String: JSONValue] = [
            "rev": .integer(revision), "item": .string(placed.itemIDs.first ?? ""),
            "items": .array(placed.itemIDs.map(JSONValue.string)), "track": .string(placed.trackID),
            "duration": .integer(placed.duration), "looped": .bool(placed.looped), "library": .string(item.reference),
        ]
        if placed.shortened {
            result["note"] = .string(
                "The sound is not loopable, so it plays once and is shorter than asked; mark it loopable with "
                    + "library update --params to repeat it")
        }
        return .object(result)
    }

    // MARK: Analysis

    /// Measures an audio item's file and saves the values as a new version (`library analyze`): its length, its
    /// loudness and true peak (an audio.loudness provider, as `audio measure`) and, unless it is a sound effect, its
    /// tempo (an audio.beats provider, as `beats detect`). A provider that is missing or fails leaves that value as it
    /// was and says why in `notes`. Agents saving to the user library wait for approval.
    func analyzeLibraryAudio(_ item: LibraryItem, provider: String? = nil, author: Author) async throws -> JSONValue {
        let audio = try libraryAudio(item)
        guard item.scope.isWritable else {
            throw RPCFailure(
                -32602, "\(item.reference) is read-only; save a copy with library update --as, then analyze the copy")
        }
        guard let url = libraryCatalog.fileURL(of: item) else { throw RPCFailure(-32602, "\(item.reference) has no file") }
        let store = try libraryCatalog.store(item.scope)
        let root = fileURL?.deletingLastPathComponent()
        var measured = LibraryAudio(seconds: try await Self.soundSeconds(url, label: item.reference))
        var notes: [String: JSONValue] = [:]
        do {
            let loudness = try await plugins.running("audio.loudness") {
                try await plugins.service.analyzeLoudness(
                    mediaURL: url, bands: false, curve: true,
                    preferredProvider: provider ?? project.preferredProvider(for: "audio.loudness"), projectRoot: root)
            }
            measured.lufs = loudness.measurement.integratedLUFS
            measured.truePeak = loudness.measurement.truePeakDbTP
            if let curve = Self.curve(loudness.measurement) {
                measured.landmarks = MixMeasure.landmarks(curve)
                if measured.landmarks == nil { notes["landmarks"] = .string("The sound never passes −70 LUFS") }
            } else {
                notes["landmarks"] = .string("The audio.loudness provider gave no curve")
            }
        } catch {
            notes["lufs"] = .string(error.localizedDescription)
        }
        if audio.placementRole(seconds: measured.seconds) == "sfx" {
            notes["bpm"] = .string("Not measured for a sound effect")
        } else {
            do {
                let beats = try await plugins.running("audio.beats") {
                    try await plugins.service.detectBeats(
                        mediaURL: url, preferredProvider: project.preferredProvider(for: "audio.beats"),
                        projectRoot: root ?? store.root)
                }
                if LibraryAudio.bpmRange.contains(beats.bpm) {
                    measured.bpm = beats.bpm
                } else {
                    notes["bpm"] = .string("No steady tempo found")
                }
            } catch {
                notes["bpm"] = .string(error.localizedDescription)
            }
        }
        let changes: [String: JSONValue]
        do { changes = try LibraryAudio.analysisChanges(item, measured: measured) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        let saved = try await libraryChange(
            "library.analyze", scope: item.scope, author: author, arguments: ["id": item.reference, "name": item.name]
        ) {
            try store.update(item.id, changes: changes).json()
        }
        return .object(["item": saved, "measured": .object(measured.params()), "notes": .object(notes)])
    }

    /// The Audio panel's Analyze: the same as `library analyze`, as the user.
    func analyzeFromLibrary(_ item: LibraryItem) {
        message = String(localized: "Analyzing “\(item.name)”…")
        Task {
            do {
                let result = try await analyzeLibraryAudio(item, author: .user)
                let notes = result.object["notes"]?.object.values.compactMap(\.string) ?? []
                message = ([String(localized: "Analyzed “\(item.name)”")] + notes).joined(separator: " · ")
            } catch { message = error.localizedDescription }
        }
    }

    // MARK: Preview

    /// Plays an audio item, or stops it when it is the one playing (the Audio panel's play button).
    func toggleLibraryPreview(_ item: LibraryItem) {
        let preview = LibraryAudioPreview.shared
        if preview.playing == item.reference {
            preview.stop()
            return
        }
        do { try playLibraryPreview(item) } catch { message = error.localizedDescription }
    }

    @discardableResult
    func playLibraryPreview(_ item: LibraryItem) throws -> Double {
        guard item.kind == .audio || item.file.map({ Self.accepts(URL(fileURLWithPath: $0), kind: .audio) }) == true else {
            throw RPCFailure(-32602, "\(item.reference) has no sound to play")
        }
        guard let url = libraryCatalog.fileURL(of: item) else { throw RPCFailure(-32602, "\(item.reference) has no file") }
        do { return try LibraryAudioPreview.shared.play(url, reference: item.reference) } catch let failure as RPCFailure {
            throw failure
        } catch {
            throw RPCFailure(-32602, "\(item.reference) cannot be played: \(error.localizedDescription)")
        }
    }

    // MARK: Saving project audio

    /// Save to Library… on project audio: the sheet for a new audio item from the media `mediaID`.
    func beginSaveAudio(mediaID: String) {
        let params: [String: JSONValue]
        do { params = try audioSelection(itemID: nil, mediaID: mediaID).params } catch {
            message = error.localizedDescription
            return
        }
        let name = project.media.first { $0.id == mediaID }
            .map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent } ?? ""
        var request = LibraryEditorRequest(
            mode: .saveSelection(.audio), name: name.isEmpty ? String(localized: "My audio") : name,
            scope: defaultLibraryScope)
        request.mediaID = mediaID
        request.audio = try? LibraryAudio(params: params)
        ui.libraryEditor = request
    }

    /// An audio item's params and file from project audio: the media `mediaID`, or the clip `itemID` (the
    /// selection by default), whose layer gives its role.
    func audioSelection(itemID: String?, mediaID: String?) throws -> (params: [String: JSONValue], file: URL?) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before saving its audio to the library")
        }
        let media: Media
        var trackRole: String?
        if let mediaID {
            guard let found = project.media.first(where: { $0.id == mediaID }) else {
                throw RPCFailure(-32602, "Unknown media \(mediaID)")
            }
            media = found
            trackRole = project.tracks.first { $0.kind == TrackKind.audio && $0.items.contains { $0.mediaID == mediaID } }?.role
        } else {
            guard let id = itemID ?? selectedID else {
                throw RPCFailure(-32602, "Select an audio clip, or pass --item or --media")
            }
            guard let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
                let item = track.items.first(where: { $0.id == id })
            else { throw RPCFailure(-32602, "Unknown item \(id)") }
            guard track.kind == TrackKind.audio, let found = project.media.first(where: { $0.id == item.mediaID }) else {
                throw RPCFailure(-32602, "\(id) is not an audio clip")
            }
            media = found
            trackRole = track.role
        }
        let params: [String: JSONValue]
        do { params = try LibrarySelection.audio(media, trackRole: trackRole) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        let file = try MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace)
        return (params, file)
    }

    // MARK: Automation

    func registerLibraryAudioCommands() {
        handleAuthored("library.analyze") { document, arguments, author in
            let item = try document.libraryCatalog.item(
                try arguments.string("id"), scope: arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:)))
            _ = try document.libraryAudio(item)
            let provider = arguments.optionalString("provider")
            let job = document.jobs.start("library.analyze", author: author, detail: item.name, work: { [weak document] _ in
                guard let document else { throw CancellationError() }
                return try await document.analyzeLibraryAudio(item, provider: provider, author: author)
            }, finished: { [weak document] outcome in
                guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
                document?.message = "library.analyze: " + error.localizedDescription
            })
            return .object(["job": .string(job), "state": .string("running")])
        }
        handle("library.preview") { document, arguments, _ in
            guard !arguments.bool("stop"), let id = arguments.optionalString("id") else {
                LibraryAudioPreview.shared.stop()
                return .object(["playing": .null])
            }
            let item = try document.libraryCatalog.item(
                id, scope: arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:)))
            let seconds = try document.playLibraryPreview(item)
            return .object(["playing": .string(item.reference), "seconds": .number((seconds * 100).rounded() / 100)])
        }
    }
}
