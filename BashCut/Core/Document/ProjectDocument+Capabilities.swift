import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

private let capabilityForMethod = [
    "captions.generate": "captions.transcribe", "beats.detect": "audio.beats", "voice.speak": "voice.synthesize",
    "audio.measure": "audio.loudness", "media.sync": "audio.sync",
]

extension ProjectDocument {
    var contentLanguage: String { project["contentLanguage"]?.string ?? "vi" }

    // MARK: Shared actions for native panels and automation

    /// Transcribes one project media item and imports the SRT as one undoable edit.
    /// With `range` (source seconds), only that stretch is transcribed and replaced.
    func generateCaptions(
        mediaID: String, replace: Bool, provider: String? = nil, wordStyle: String? = nil,
        range: ClosedRange<Double>? = nil, author: Author = .user
    ) async throws {
        let (root, _, url) = try capabilityMedia(mediaID)
        let session = sessionID
        let generated = try await plugins.running("captions.transcribe") {
            try await plugins.service.transcribe(
                mediaURL: url, language: contentLanguage, range: range,
                preferredProvider: provider ?? project.preferredProvider(for: "captions.transcribe"),
                projectRoot: root,
                outputRoot: root.appendingPathComponent("subtitles/generated", isDirectory: true))
        }
        try ensureSession(session)
        try commit(
            project.importingSubRip(
                generated.text, replace: replace, provenance: generated.provenance.json, media: mediaID,
                words: generated.words, wordStyle: wordStyle, range: range),
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
            let sourceEnd = sourceStart + item.sourceSeconds(afterFrames: item.duration, fps: project.fps)
            for second in generated.beatSeconds where second >= sourceStart && second <= sourceEnd {
                // Through trim, speed and any speed ramp.
                let frame = item.at + Int(item.timelineFrames(atSourceSeconds: second - sourceStart, fps: project.fps).rounded())
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

    /// Loudness, loudness range and speech-band shares of one media item.
    func measureAudio(mediaID: String, provider: String? = nil) async throws -> JSONValue {
        let (root, media, url) = try capabilityMedia(mediaID)
        let generated = try await plugins.running("audio.loudness") {
            try await plugins.service.analyzeLoudness(
                mediaURL: url, bands: true, preferredProvider: provider ?? project.preferredProvider(for: "audio.loudness"),
                projectRoot: root)
        }
        guard case .object(var fields) = generated.measurement.json else { return generated.measurement.json }
        fields["media"] = .string(media.id)
        fields["seconds"] = .number((Double(media.frames) / media.fps.value * 100).rounded() / 100)
        fields["provider"] = .object(generated.provenance.json)
        return .object(fields)
    }

    /// The offset between two recordings of one moment: time in `otherID` = time in `mediaID` + offsetSeconds.
    /// With `itemID` (a clip of `mediaID`), also the source frame of `otherID` matching the clip's in-point.
    func syncMedia(mediaID: String, otherID: String, itemID: String? = nil, provider: String? = nil) async throws
        -> JSONValue
    {
        guard mediaID != otherID else { throw ProjectError.invalid("Pick two different media items to sync") }
        let (root, media, url) = try capabilityMedia(mediaID)
        let (_, other, otherURL) = try capabilityMedia(otherID)
        let item = try itemID.map { id in
            guard let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }) else {
                throw ProjectError.invalid("Unknown item \(id)")
            }
            guard item.mediaID == media.id else { throw ProjectError.invalid("Item \(id) is not a clip of \(media.id)") }
            return item
        }
        let generated = try await plugins.running("audio.sync") {
            try await plugins.service.syncAudio(
                mediaURL: url, otherURL: otherURL,
                preferredProvider: provider ?? project.preferredProvider(for: "audio.sync"), projectRoot: root)
        }
        func match(_ value: GeneratedAudioSync.Match) -> JSONValue {
            .object(["offsetSeconds": .number(value.offsetSeconds), "correlation": .number(value.correlation)])
        }
        var fields: [String: JSONValue] = [
            "media": .string(media.id), "to": .string(other.id),
            "offsetSeconds": .number(generated.match.offsetSeconds), "correlation": .number(generated.match.correlation),
            "halves": .array(generated.halves.map(match)), "steady": .bool(generated.isSteady),
            "reliable": .bool(generated.match.correlation >= 0.4 && generated.isSteady),
            "meaning": .string("time in \(other.id) = time in \(media.id) + offsetSeconds"),
            "provider": .object(generated.provenance.json),
        ]
        if let overlap = generated.overlap {
            fields["overlapSeconds"] = .array([.number(overlap.lowerBound), .number(overlap.upperBound)])
        }
        if let item {
            let seconds = Double(item.sourceIn) / media.fps.value + generated.match.offsetSeconds
            let frame = Int((seconds * other.fps.value).rounded())
            fields["item"] = .object([
                "item": .string(item.id), "at": .integer(item.at),
                "otherSourceIn": .integer(frame), "otherSourceSeconds": .number((seconds * 1000).rounded() / 1000),
                "inside": .bool(frame >= 0 && frame < other.frames),
            ])
        }
        return .object(fields)
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

    func ensureSession(_ session: UUID) throws {
        guard session == sessionID else { throw CancellationError() }
    }

    // MARK: Automation

    func registerCapabilityCommands() {
        handle("plugins.list") { document, arguments, _ in
            await document.plugins.loadCachedRegistry()
            let category = arguments.optionalString("category").flatMap(PluginCategory.init(rawValue:))
            return document.pluginCatalogJSON(category: category)
        }
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
            let wordStyle = arguments.optionalString("wordStyle").flatMap { $0 == "none" ? nil : $0 }
            let from = arguments.optionalDouble("from"), to = arguments.optionalDouble("to")
            var range: ClosedRange<Double>?
            if from != nil || to != nil {
                let lower = from ?? 0, upper = to ?? 86_400
                guard upper > lower else { throw RPCFailure(-32602, "to must be after from") }
                range = lower...upper
            }
            return try document.startCapabilityJob("captions.generate", author: author) { document in
                try await document.generateCaptions(
                    mediaID: media, replace: replace, provider: provider, wordStyle: wordStyle, range: range,
                    author: author)
                return .object(["rev": .integer(document.project.revision)])
            }
        }
        handleAuthored("audio.measure") { document, arguments, author in
            let media = try arguments.string("media")
            let provider = arguments.optionalString("provider")
            return try document.startCapabilityJob("audio.measure", author: author) { document in
                try await document.measureAudio(mediaID: media, provider: provider)
            }
        }
        handleAuthored("media.sync") { document, arguments, author in
            let media = try arguments.string("media")
            let other = try arguments.string("to")
            let item = arguments.optionalString("item")
            let provider = arguments.optionalString("provider")
            guard media != other else { throw RPCFailure(-32602, "Pick two different media items to sync") }
            return try document.startCapabilityJob("media.sync", author: author) { document in
                try await document.syncMedia(mediaID: media, otherID: other, itemID: item, provider: provider)
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

    private func pluginCatalogJSON(category: PluginCategory? = nil) -> JSONValue {
        let result = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        let listed = result.plugins.filter { category == nil || plugins.category(of: $0) == category }
        return .object([
            "plugins": .array(listed.map { plugin in
                let availability = plugins.currentAvailability(plugin)
                return .object([
                    "id": .string(plugin.id), "name": .string(plugin.manifest.displayName),
                    "category": .string(plugins.category(of: plugin).rawValue),
                    "version": .string(plugin.manifest.version), "apiVersion": .integer(plugin.manifest.apiVersion),
                    "availability": .string(availability.name),
                    "detail": .string(availability.detail),
                    "transport": .string(plugin.manifest.transportKind.rawValue),
                    "source": plugins.origin(of: plugin).map { origin in
                        .object(["url": .string(origin.url), "resolved": origin.resolved.map(JSONValue.string) ?? .null,
                                 "sha256": .string(origin.sha256)])
                    } ?? .null,
                    "linked": plugins.linkTarget(of: plugin).map { .string($0.path) } ?? .null,
                    "hooksEnabled": .bool(plugins.trust.hooksEnabled(plugin)),
                    "actions": .array(plugin.manifest.actions.map { .string($0.id) }),
                    "hooks": .array(plugin.manifest.hooks.map { .string($0.event) }),
                    "options": .array((plugin.manifest.options ?? []).map { .string($0.id) }),
                    "library": .array(plugin.manifest.libraryPacks.map { .string($0.path) }),
                    // Skills it ships (API 7); agents get them only while the plugin is ready.
                    "skills": .array(plugins.skills(of: plugin).map { skill in
                        .object(["name": .string(skill.id), "description": .string(skill.description),
                                 "path": .string(skill.file.path)])
                    }),
                    // API 8: the rail panel, its views, required plugins and capabilities it invokes.
                    "container": plugin.manifest.container.map { _ in .string(plugin.manifest.containerTitle) } ?? .null,
                    "views": .array(plugin.manifest.views.map { .string($0.id) }),
                    "requires": plugins.requirementsJSON(plugin),
                    "uses": .array(plugin.manifest.usedCapabilities.map(JSONValue.string)),
                    "providers": .array((plugin.manifest.providers ?? []).map { provider in
                        .object([
                            "id": .string(provider.id), "capability": .string(provider.capability),
                            "name": .string(provider.name), "priority": .integer(provider.priority),
                            "kinds": provider.kinds.map { .array($0.map(JSONValue.string)) } ?? .null,
                        ])
                    }),
                ])
            }),
            "preferences": project["providers"] ?? .object([:]),
            "diagnostics": .array((result.diagnostics + plugins.library.problems).map(JSONValue.string)),
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
