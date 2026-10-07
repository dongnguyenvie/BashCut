import AVFoundation
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

extension ProjectDocument {
    /// The project's speech language; empty when not set (providers detect it, context get reports null).
    var contentLanguage: String { project["contentLanguage"]?.string ?? "" }

    // MARK: Shared actions for native panels and automation

    /// Transcribes one project media item and imports its captions as one undoable edit. The whole file is
    /// transcribed once and kept as its source transcript (`media.transcribe`); later calls place captions from it
    /// unless `fresh`, or when it was made in another language or by another provider than `provider`.
    /// With `range` (source seconds), only that stretch is replaced; without a stored transcript only that stretch
    /// is transcribed (and not kept). Returns how the words were found: `stored`, `transcribed` or `range`.
    @discardableResult
    func generateCaptions(
        mediaID: String, replace: Bool, provider: String? = nil, wordStyle: String? = nil,
        range: ClosedRange<Double>? = nil, fresh: Bool = false, author: Author = .user
    ) async throws -> String {
        let session = sessionID
        let phrases: [SubRip.Cue], words: [CaptionWords.Timed], provenance: [String: JSONValue], how: String
        if !fresh, let stored = try await reusableTranscript(mediaID, provider: provider) {
            (phrases, words, provenance, how) = (stored.phrases, stored.words, stored.provider, "stored")
        } else if range == nil {
            let transcript = try await transcribeSource(mediaID, provider: provider)
            (phrases, words, provenance, how) = (transcript.phrases, transcript.words, transcript.provider, "transcribed")
        } else {
            let generated = try await transcribe(mediaID, provider: provider, range: range)
            (phrases, words, provenance, how) = (
                try SubRip.cues(generated.text), generated.words, generated.provenance.json, "range"
            )
        }
        try ensureSession(session)
        // The file the words were heard in, so review can say when it changes later (P2-G6).
        var keyed = provenance
        if let key = sourceKey(mediaID) { keyed["sourceKey"] = .string(key) }
        try commit(
            project.importingCues(
                phrases, replace: replace, provenance: keyed, media: mediaID, words: words, wordStyle: wordStyle,
                range: range),
            label: "Generate captions", author: author)
        emitPluginEvent(.captionsGenerated, [
            "media": .string(mediaID), "provider": .object(provenance), "rev": .integer(project.revision),
        ])
        return how
    }

    /// Runs `captions.transcribe` on one media (or the `range` of it, in source seconds).
    func transcribe(
        _ mediaID: String, provider: String?, range: ClosedRange<Double>? = nil
    ) async throws -> GeneratedPluginCaptions {
        let (root, _, url) = try capabilityMedia(mediaID)
        return try await plugins.running("captions.transcribe") {
            try await plugins.service.transcribe(
                mediaURL: url, language: contentLanguage, range: range,
                preferredProvider: provider ?? project.preferredProvider(for: "captions.transcribe"),
                projectRoot: root,
                outputRoot: root.appendingPathComponent("subtitles/generated", isDirectory: true))
        }
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
                provenance: generated.provenance.json.merging(
                    sourceKey(media.id).map { ["sourceKey": .string($0)] } ?? [:]) { _, new in new }),
            label: "Detect beats", author: author)
        try? storeBeatGrid(generated, url: url, root: root)
        emitPluginEvent(.beatsDetected, [
            "media": .string(media.id), "bpm": .number(generated.bpm), "beats": .integer(frames.count),
        ])
    }

    /// Loudness, loudness range and speech-band shares of one media item.
    func measureAudio(mediaID: String, provider: String? = nil, curve: Bool = false) async throws -> JSONValue {
        let (root, media, url) = try capabilityMedia(mediaID)
        let generated = try await plugins.running("audio.loudness") {
            try await plugins.service.analyzeLoudness(
                mediaURL: url, bands: true, curve: curve,
                preferredProvider: provider ?? project.preferredProvider(for: "audio.loudness"), projectRoot: root)
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

    /// `cloneConsent`: the person asking agreed to clone a voice; the Voice panel passes it for the user, agents only
    /// when told to.
    func generateVoiceTakes(
        text: String, count: Int = 3, provider: String? = nil, cloneConsent: Bool = false
    ) async throws -> [GeneratedVoiceTake] {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before generating voiceover")
        }
        let session = sessionID
        let takes = try await plugins.running("voice.synthesize") {
            try await plugins.service.synthesizeVoiceTakes(
                text: text, language: contentLanguage, count: count,
                preferredProvider: provider ?? project.preferredProvider(for: "voice.synthesize"),
                projectRoot: root, outputRoot: root.appendingPathComponent("voiceover/generated", isDirectory: true),
                cloneConsent: cloneConsent)
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
        _ asset: GeneratedPluginAsset, at frame: Int? = nil, voice: [String: JSONValue]? = nil, author: Author = .user
    ) async throws -> String {
        try await insertVoiceTake(
            VoiceTakeFile(asset, voice: voice), at: frame, voice: voice, author: author)
    }

    /// Inserts a take file with its recorded provenance on the Voiceover track and returns the new item ID.
    @discardableResult
    func insertVoiceTake(
        _ take: VoiceTakeFile, at frame: Int?, voice: [String: JSONValue]?, author: Author
    ) async throws -> String {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a project before generating voiceover")
        }
        let session = sessionID
        let mediaAsset = AVURLAsset(url: take.url)
        let duration = try await mediaAsset.load(.duration)
        let hasAudio = try await !mediaAsset.loadTracks(withMediaType: .audio).isEmpty
        try ensureSession(session)
        let frames = Int((duration.seconds * project.fps.value).rounded(.down))
        guard frames > 0, hasAudio else { throw ProjectError.invalid("Voice plugin output is not a valid audio file") }
        let start = frame ?? playhead
        guard start >= 0 else { throw ProjectError.invalid("Voiceover start frame must not be negative") }
        let mediaID = UUID().uuidString
        let media = Media(fields: [
            "id": .string(mediaID), "path": .string(Self.relativePath(take.url, root: root)),
            "kind": .string("audio"), "fps": project.fps.json, "frames": .integer(frames),
            "generatedBy": .object(take.generatedBy), "provenance": take.provenance,
        ])
        var item = Item(media: mediaID, at: start, duration: frames)
        if let voice { item["voice"] = .object(voice) }
        let track = try project.requireTrack(role: TrackRole.voiceover, kind: "audio")
        try commit(
            .group(
                label: "Generate voiceover", author: author,
                ops: [.addMedia(media), .insert(track: track.id, item: item)]),
            label: "Generate voiceover", author: author)
        selectedID = item.id
        selectedTrackID = track.id
        emitPluginEvent(.voiceGenerated, [
            "item": .string(item.id), "media": .string(mediaID), "path": .string(take.url.path),
        ])
        return item.id
    }

    /// The current content key of a media file (`SourceHash.mediaNamespace`, P2-G6); nil when it cannot be read.
    func sourceKey(_ mediaID: String) -> String? {
        guard let (_, _, url) = try? capabilityMedia(mediaID) else { return nil }
        return try? ProjectCache.contentKey(for: url, namespace: SourceHash.mediaNamespace)
    }

    /// Current content keys of the media review checks results against (P2-G6).
    func sourceMediaKeys() -> [String: String] {
        Dictionary(uniqueKeysWithValues: project.sourceKeyedMedia.compactMap { id in sourceKey(id).map { (id, $0) } })
    }

    /// A voice take's `provenance` (P2-H8): made by AI, by which provider, for which request and what it was charged.
    static func voiceTakeProvenance(_ asset: GeneratedPluginAsset) -> JSONValue {
        var fields = asset.provenance.json
        fields["origin"] = .string("ai")
        let call = PluginCallContext.current
        if let requestID = call.requestID { fields["requestId"] = .string(requestID) }
        if let charged = call.usage?.json["costUSD"]?.double { fields["charged"] = .number(charged) }
        return .object(fields)
    }

    /// A voice take's `generatedBy`: the provider, plus the hash of the text it says.
    static func voiceProvenance(_ asset: GeneratedPluginAsset, voice: [String: JSONValue]?) -> [String: JSONValue] {
        var fields = asset.provenance.json
        if let hash = voice?["textHash"] { fields["textHash"] = hash }
        return fields
    }

    func capabilityMedia(_ mediaID: String) throws -> (URL, Media, URL) {
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
        handle("plugins.list") { document, arguments, _ in try await document.pluginsList(arguments) }
        handle("jobs.status") { document, arguments, _ in
            if let id = arguments.optionalString("job") {
                guard let job = document.jobs.job(id) else { throw RPCFailure(-32602, "Unknown job") }
                return job.json
            }
            return .array(document.jobs.jobs.map(\.json))
        }
        handle("capabilities.get") { document, arguments, _ in try await document.capabilitiesJSON(arguments) }
        handle("jobs.wait") { document, arguments, _ in
            try await document.waitForJob(try arguments.string("job"), seconds: try arguments.int("timeout"))
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
            let fresh = arguments.bool("fresh")
            return try await document.startCapabilityJob("captions.generate", author: author, arguments: arguments) { document in
                let words = try await document.generateCaptions(
                    mediaID: media, replace: replace, provider: provider, wordStyle: wordStyle, range: range,
                    fresh: fresh, author: author)
                return .object(["rev": .integer(document.project.revision), "transcript": .string(words)])
            }
        }
        handleAuthored("audio.measure") { document, arguments, author in
            let provider = arguments.optionalString("provider")
            if arguments.bool("timeline") {
                return try await document.startCapabilityJob("audio.measure", author: author, arguments: arguments) { document in
                    try await document.measureTimelineAudio(provider: provider)
                }
            }
            guard let media = arguments.optionalString("media") else { throw RPCFailure(-32602, "Give media, or timeline") }
            let curve = arguments.bool("curve")
            return try await document.startCapabilityJob("audio.measure", author: author, arguments: arguments) { document in
                try await document.measureAudio(mediaID: media, provider: provider, curve: curve)
            }
        }
        handleAuthored("audio.mix-measure") { document, arguments, author in
            let provider = arguments.optionalString("provider")
            let near = arguments.optionalDouble("nearSeconds") ?? 1
            return try await document.startCapabilityJob("audio.mix-measure", author: author, arguments: arguments) { document in
                try await document.measureMix(provider: provider, nearSeconds: near)
            }
        }
        handleAuthored("media.sync") { document, arguments, author in
            let media = try arguments.string("media")
            let other = try arguments.string("to")
            let item = arguments.optionalString("item")
            let provider = arguments.optionalString("provider")
            guard media != other else { throw RPCFailure(-32602, "Pick two different media items to sync") }
            return try await document.startCapabilityJob("media.sync", author: author, arguments: arguments) { document in
                try await document.syncMedia(mediaID: media, otherID: other, itemID: item, provider: provider)
            }
        }
        handleAuthored("beats.detect") { document, arguments, author in
            let media = try arguments.string("media")
            let provider = arguments.optionalString("provider")
            return try await document.startCapabilityJob("beats.detect", author: author, arguments: arguments) { document in
                try await document.detectBeats(mediaID: media, provider: provider, author: author)
                return .object([
                    "rev": .integer(document.project.revision),
                    "bpm": document.project.beatBPM.map(JSONValue.number) ?? .null,
                    "beats": .integer(document.project.beatFrames.count),
                    "grid": (try? document.storedBeatGrid(media))?.object["grid"] ?? .null,
                ])
            }
        }
    }

    func pluginCatalogJSON(category: PluginCategory? = nil) -> JSONValue {
        let result = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        let listed = result.plugins.filter { category == nil || plugins.category(of: $0) == category }
        return .object([
            "plugins": .array(listed.map { plugin in
                let availability = plugins.currentAvailability(plugin)
                return .object([
                    "id": .string(plugin.id), "name": .string(plugin.manifest.displayName),
                    "category": .string(plugins.category(of: plugin).rawValue),
                    "version": .string(plugin.manifest.version), "apiVersion": .integer(plugin.manifest.apiVersion),
                    "author": plugin.manifest.author?.json ?? .null,
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

    /// A capability report with the commands that call it.
    static func capabilityJSON(_ report: CapabilityReport) -> JSONValue {
        var fields = report.json.object
        fields["commands"] = .array(
            CommandCatalog.capabilities.filter { $0.value == report.capability }.keys.sorted().map(JSONValue.string))
        return .object(fields)
    }

    /// `jobs.wait` (P2-G4): the job once its state or step changes, it finishes, or `seconds` pass.
    func waitForJob(_ id: String, seconds: Int) async throws -> JSONValue {
        guard jobs.job(id) != nil else { throw RPCFailure(-32602, "Unknown job") }
        guard let (job, changed) = try await jobs.wait(id, for: .seconds(seconds)) else {
            throw RPCFailure(-32602, "The job is gone: the project was closed or switched")
        }
        return .object(["job": job.json, "changed": .bool(changed), "timedOut": .bool(job.isActive && !changed)])
    }

    /// The job an earlier request with the same `requestID` started (P2-G4), as `{job, state, reused}`.
    func reusedJob(_ method: String, requestID: String?) -> JSONValue? {
        guard let requestID, let job = jobs.job(method: method, requestID: requestID) else { return nil }
        return .object(["job": .string(job.id), "state": .string(job.state.rawValue), "reused": .bool(true)])
    }

    /// Runs `work` with plugin calls frozen instead of sent (P2-G4) and returns the first request it would send.
    func capabilityDryRun(_ work: @MainActor (ProjectDocument) async throws -> JSONValue) async throws -> JSONValue {
        do {
            _ = try await PluginCallContext.$current.withValue(PluginCallContext(dryRun: true)) { try await work(self) }
        } catch let dryRun as PluginDryRun {
            return .object(["dryRun": .bool(true), "request": dryRun.request])
        }
        throw RPCFailure(-32602, "This request would not call a plugin provider")
    }

    /// Starts a provider job for `method`. With `arguments`, its `requestId` returns the job an earlier request with
    /// the same ID started, and `dryRun` returns the request the provider would get, without running (D8).
    func startCapabilityJob(
        _ method: String, author: Author, arguments: CommandArguments? = nil, requestID: String? = nil,
        work: @escaping @MainActor (ProjectDocument) async throws -> JSONValue
    ) async throws -> JSONValue {
        if arguments?.bool("dryRun") == true { return try await capabilityDryRun(work) }
        let requestID = requestID ?? arguments?.optionalString("requestId")
        if let reused = reusedJob(method, requestID: requestID) { return reused }
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        // Fail the call, not a job a moment later, when nothing could serve it (P2-G5; health is checked in the job).
        if let capability = CommandCatalog.capabilities[method] {
            let report = plugins.service.capabilityStatus(capability, projectRoot: root)
            if !report.available { throw CapabilityUnavailable(report) }
        }
        guard !conflict else { throw RPCFailure(-32003, "The project has a file conflict; retry later", category: .fileConflict) }
        if let capability = CommandCatalog.capabilities[method], plugins.calling.contains(capability) {
            throw RPCFailure(-32003, "\(capability) is already running; retry later", category: .busyRunning)
        }
        let id = jobs.start(method, author: author, requestID: requestID, work: { [weak self] _ in
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
