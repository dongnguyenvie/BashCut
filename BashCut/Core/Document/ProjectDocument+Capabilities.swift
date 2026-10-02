import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

private let capabilityForMethod = [
    "captions.generate": "captions.transcribe", "beats.detect": "audio.beats", "voice.speak": "voice.synthesize",
]

extension ProjectDocument {
    var contentLanguage: String { project.fields["contentLanguage"]?.string ?? "vi" }

    // MARK: Shared actions for native panels and automation

    /// Transcribes one project media item and imports the SRT as one undoable edit.
    func generateCaptions(
        mediaID: String, replace: Bool, provider: String? = nil, author: Author = .user
    ) async throws {
        let (root, _, url) = try capabilityMedia(mediaID)
        let session = sessionID
        let generated = try await plugins.running("captions.transcribe") {
            try await plugins.service.transcribe(
                mediaURL: url, language: contentLanguage,
                preferredProvider: provider ?? project.preferredProvider(for: "captions.transcribe"),
                projectRoot: root,
                outputRoot: root.appendingPathComponent("subtitles/generated", isDirectory: true))
        }
        try ensureSession(session)
        try commit(
            project.importingSubRip(generated.text, replace: replace, provenance: generated.provenance.json),
            label: "Generate captions", author: author)
        emitPluginEvent(.captionsGenerated, [
            "media": .string(mediaID), "provider": .object(generated.provenance.json), "rev": .integer(project.revision),
        ])
    }

    /// Detects beats in an audio media item and maps them through its timeline items to integer frames.
    func detectBeats(mediaID: String, provider: String? = nil, author: Author = .user) async throws {
        let (root, media, url) = try capabilityMedia(mediaID)
        guard media["kind"] == .string("audio") else {
            throw ProjectError.invalid("Beat detection requires an audio media item")
        }
        let session = sessionID
        let generated = try await plugins.running("audio.beats") {
            try await plugins.service.detectBeats(
                mediaURL: url, preferredProvider: provider ?? project.preferredProvider(for: "audio.beats"),
                projectRoot: root)
        }
        try ensureSession(session)
        var frames = Set<Int>()
        for item in project.tracks.flatMap(\.items) where item.mediaID == media.id {
            let sourceStart = Double(item.sourceIn) / media.fps.value
            let sourceEnd = sourceStart + Double(item.duration) / project.fps.value * item.speed
            for second in generated.beatSeconds where second >= sourceStart && second <= sourceEnd {
                let frame = item.at + Int(((second - sourceStart) / item.speed * project.fps.value).rounded())
                if frame >= item.at && frame <= item.end { frames.insert(frame) }
            }
        }
        guard !frames.isEmpty else {
            throw ProjectError.invalid("Insert the selected audio into the timeline before detecting beats")
        }
        try commit(
            .setBeatGrid(
                media: media.id, bpm: generated.bpm, frames: frames.sorted(),
                provenance: generated.provenance.json),
            label: "Detect beats", author: author)
        emitPluginEvent(.beatsDetected, [
            "media": .string(media.id), "bpm": .number(generated.bpm), "beats": .integer(frames.count),
        ])
    }

    func generateVoiceTakes(
        text: String, count: Int = 3, provider: String? = nil
    ) async throws -> [GeneratedVoiceTake] {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before generating voiceover")
        }
        let session = sessionID
        let takes = try await plugins.running("voice.synthesize") {
            try await plugins.service.synthesizeVoiceTakes(
                text: text, language: contentLanguage, count: count,
                preferredProvider: provider ?? project.preferredProvider(for: "voice.synthesize"),
                projectRoot: root, outputRoot: root.appendingPathComponent("voiceover/generated", isDirectory: true))
        }
        guard session == sessionID else {
            CapabilityService.discardVoiceTakes(takes)
            throw CancellationError()
        }
        return takes
    }

    /// Inserts one generated take on the Voiceover track and returns the new item ID.
    @discardableResult
    func insertVoiceTake(
        _ asset: GeneratedPluginAsset, at frame: Int? = nil, author: Author = .user
    ) async throws -> String {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before generating voiceover")
        }
        let session = sessionID
        let mediaAsset = AVURLAsset(url: asset.url)
        let duration = try await mediaAsset.load(.duration)
        let hasAudio = try await !mediaAsset.loadTracks(withMediaType: .audio).isEmpty
        try ensureSession(session)
        let frames = Int((duration.seconds * project.fps.value).rounded(.down))
        guard frames > 0, hasAudio else { throw ProjectError.invalid("Voice plugin output is not a valid audio file") }
        let start = frame ?? playhead
        guard start >= 0 else { throw ProjectError.invalid("Voiceover start frame must not be negative") }
        let mediaID = UUID().uuidString
        let media = Media(fields: [
            "id": .string(mediaID), "path": .string(Self.relativePath(asset.url, root: root)),
            "kind": .string("audio"), "fps": project.fps.json, "frames": .integer(frames),
            "generatedBy": .object(asset.provenance.json),
        ])
        let item = Item(media: mediaID, at: start, duration: frames)
        let track = try project.requireTrack(role: TrackRole.voiceover, kind: "audio")
        try commit(
            .group(
                label: "Generate voiceover", author: author,
                ops: [.addMedia(media), .insert(track: track.id, item: item)]),
            label: "Generate voiceover", author: author)
        selectedID = item.id
        selectedTrackID = track.id
        emitPluginEvent(.voiceGenerated, [
            "item": .string(item.id), "media": .string(mediaID), "path": .string(asset.url.path),
        ])
        return item.id
    }

    private func capabilityMedia(_ mediaID: String) throws -> (URL, Media, URL) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a saved project first")
        }
        guard let media = project.media.first(where: { $0.id == mediaID }) else {
            throw ProjectError.invalid("Unknown media \(mediaID)")
        }
        let url = try MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace)
        return (root, media, url)
    }

    private func ensureSession(_ session: UUID) throws {
        guard session == sessionID else { throw CancellationError() }
    }

    // MARK: Automation

    func registerCapabilityCommands() {
        handle("plugins.list") { document, _, _ in document.pluginCatalogJSON() }
        handle("jobs.status") { document, arguments, _ in
            if let id = arguments.optionalString("job") {
                guard let job = document.jobs.job(id) else { throw RPCFailure(-32602, "Unknown job") }
                return job.json
            }
            return .array(document.jobs.jobs.map(\.json))
        }
        handleAuthored("jobs.cancel") { document, arguments, _ in
            guard document.jobs.cancel(try arguments.string("job")) else {
                throw RPCFailure(-32602, "job must name a queued or running job")
            }
            return .bool(true)
        }
        handleAuthored("captions.generate") { document, arguments, author in
            let media = try arguments.string("media")
            let replace = arguments.bool("replace")
            let provider = arguments.optionalString("provider")
            return try document.startCapabilityJob("captions.generate", author: author) { document in
                try await document.generateCaptions(
                    mediaID: media, replace: replace, provider: provider, author: author)
                return .object(["rev": .integer(document.project.revision)])
            }
        }
        handleAuthored("beats.detect") { document, arguments, author in
            let media = try arguments.string("media")
            let provider = arguments.optionalString("provider")
            return try document.startCapabilityJob("beats.detect", author: author) { document in
                try await document.detectBeats(mediaID: media, provider: provider, author: author)
                return .object([
                    "rev": .integer(document.project.revision),
                    "bpm": document.project.beatBPM.map(JSONValue.number) ?? .null,
                    "beats": .integer(document.project.beatFrames.count),
                ])
            }
        }
        handleAuthored("voice.speak") { document, arguments, author in
            let text = try arguments.string("text")
            let count = try arguments.int("takes")
            let frame = arguments.optionalInt("atFrame")
            let provider = arguments.optionalString("provider")
            let keepTakes = arguments.bool("keepTakes")
            return try document.startCapabilityJob("voice.speak", author: author) { document in
                if keepTakes { return try await document.generateKeptTakes(text: text, count: count, provider: provider) }
                return try await document.speak(text: text, count: count, frame: frame, provider: provider, author: author)
            }
        }
    }

    /// Generates takes, inserts the best-scoring one and removes the rest.
    private func speak(
        text: String, count: Int, frame: Int?, provider: String?, author: Author
    ) async throws -> JSONValue {
        let takes = try await generateVoiceTakes(text: text, count: count, provider: provider)
        guard let best = takes.best else { throw ProjectError.invalid("Voice provider returned no takes") }
        let itemID: String
        do {
            itemID = try await insertVoiceTake(best.asset, at: frame, author: author)
        } catch {
            CapabilityService.discardVoiceTakes(takes)
            throw error
        }
        CapabilityService.discardVoiceTakes(takes, keeping: best.asset.url)
        return .object([
            "rev": .integer(project.revision), "item": .string(itemID),
            "score": .number(best.score), "scoreSource": .string(best.scoreSource),
            "takes": .array(takes.map { .object(["score": .number($0.score), "seconds": .number($0.durationSeconds)]) }),
        ])
    }

    /// Generates takes and keeps every file (like the Voice panel's take list) without inserting one.
    private func generateKeptTakes(text: String, count: Int, provider: String?) async throws -> JSONValue {
        let takes = try await generateVoiceTakes(text: text, count: count, provider: provider)
        let root = fileURL?.deletingLastPathComponent()
        return .object([
            "best": takes.best.map { .string($0.asset.url.path) } ?? .null,
            "takes": .array(takes.map { take in
                .object([
                    "path": .string(take.asset.url.path),
                    "projectPath": root.map { .string(MediaPathResolver.projectPath(for: take.asset.url, projectRoot: $0)) }
                        ?? .null,
                    "score": .number(take.score), "scoreSource": .string(take.scoreSource),
                    "seconds": .number(take.durationSeconds),
                ])
            }),
        ])
    }

    private func pluginCatalogJSON() -> JSONValue {
        let result = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        return .object([
            "plugins": .array(result.plugins.map { plugin in
                .object([
                    "id": .string(plugin.id), "name": .string(plugin.manifest.displayName),
                    "version": .string(plugin.manifest.version), "apiVersion": .integer(plugin.manifest.apiVersion),
                    "availability": .string(plugins.service.availability(plugin).name),
                    "detail": .string(plugins.service.availability(plugin).detail),
                    "transport": .string(plugin.manifest.transportKind.rawValue),
                    "hooksEnabled": .bool(plugins.trust.hooksEnabled(plugin.id)),
                    "actions": .array(plugin.manifest.actions.map { .string($0.id) }),
                    "hooks": .array(plugin.manifest.hooks.map { .string($0.event) }),
                    "options": .array((plugin.manifest.options ?? []).map { .string($0.id) }),
                    "providers": .array((plugin.manifest.providers ?? []).map { provider in
                        .object([
                            "id": .string(provider.id), "capability": .string(provider.capability),
                            "name": .string(provider.name), "priority": .integer(provider.priority),
                        ])
                    }),
                ])
            }),
            "preferences": project["providers"] ?? .object([:]),
            "diagnostics": .array(result.diagnostics.map(JSONValue.string)),
            "running": .array(plugins.calling.sorted().map(JSONValue.string)),
            "hostApiVersion": .integer(PluginAPI.current),
        ])
    }

    private func startCapabilityJob(
        _ method: String, author: Author,
        work: @escaping @MainActor (ProjectDocument) async throws -> JSONValue
    ) throws -> JSONValue {
        guard fileURL != nil else { throw RPCFailure(-32602, "Open a saved project first") }
        guard !conflict else { throw RPCFailure(-32003, "The project has a file conflict; retry later") }
        if let capability = capabilityForMethod[method], plugins.calling.contains(capability) {
            throw RPCFailure(-32003, "\(capability) is already running; retry later")
        }
        let id = jobs.start(method, author: author, work: { [weak self] _ in
            guard let self else { throw CancellationError() }
            return try await work(self)
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = method + ": " + error.localizedDescription
        })
        message = author.rawValue.capitalized + ": " + method
        return .object(["job": .string(id), "state": .string("running")])
    }
}
