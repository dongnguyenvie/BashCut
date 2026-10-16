import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import Foundation

/// The timeline's sound measured without exporting (#471, P0-B9): `audio.measure --timeline` renders the mix to a
/// scratch file and measures it with its loudness over time and silent stretches; `audio.mix-measure` renders one
/// stem per role (speech, music, sound effects) and reads them against each other.
extension ProjectDocument {
    /// The roles a stem keeps. Speech is the dialogue and voiceover layers and the sound of video clips.
    enum Stem: String, CaseIterable {
        case speech, music, effects

        func keeps(_ track: Track) -> Bool {
            switch self {
            case .speech: track.role == TrackRole.dialogue || track.role == TrackRole.voiceover || track.kind == TrackKind.video
            case .music: track.role == TrackRole.music
            case .effects: track.role == TrackRole.sfx
            }
        }
    }

    /// The project with every sound outside `stem` at −120 dB. Items stay in place, so music still ducks under
    /// speech as it does in the mix.
    func stemProject(_ stem: Stem, of project: Project? = nil) -> Project {
        var copy = project ?? self.project
        copy.revision = 0
        for index in copy.tracks.indices where !stem.keeps(copy.tracks[index]) {
            guard copy.tracks[index].kind == TrackKind.audio || copy.tracks[index].kind == TrackKind.video else { continue }
            for item in copy.tracks[index].items.indices {
                copy.tracks[index].items[item]["volumeDb"] = .number(-120)
                if var keys = copy.tracks[index].items[item]["keyframes"]?.object {
                    keys["volume"] = nil
                    copy.tracks[index].items[item]["keyframes"] = keys.isEmpty ? nil : .object(keys)
                }
            }
        }
        return copy
    }

    /// Renders `project`'s sound to a scratch file and measures it with its loudness curve; `progress` hears the
    /// render's share done.
    func measureRendered(
        _ project: Project, provider: String?, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LoudnessMeasurement {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let folder = ProjectCache.url(.loudness, projectRoot: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: file) }
        let snapshot = try await engine.build(project, root: root, workspace: settings.workspace, purpose: .export)
        _ = try await engine.exportAudio(snapshot, to: file, progress: progress)
        return try await plugins.running("audio.loudness") {
            try await plugins.service.analyzeLoudness(
                mediaURL: file, bands: false, curve: true,
                preferredProvider: provider ?? project.preferredProvider(for: "audio.loudness"), projectRoot: root)
        }.measurement
    }

    static func curve(_ measurement: LoudnessMeasurement) -> MixMeasure.Curve? {
        measurement.curve.map { MixMeasure.Curve(step: $0.step, momentary: $0.momentary, peakDb: $0.peakDb) }
    }

    /// `audio.measure --timeline`: the mix's loudness, its curve and silent stretches.
    func measureTimelineAudio(provider: String?) async throws -> JSONValue {
        guard project.tracks.contains(where: { $0.kind == TrackKind.audio || $0.kind == TrackKind.video }),
            project.duration > 0
        else { throw RPCFailure(-32602, "The timeline has no sound") }
        let measured = try await measureRendered(project, provider: provider)
        guard case .object(var fields) = measured.json else { return measured.json }
        fields["timeline"] = .bool(true)
        fields["revision"] = .integer(project.revision)
        if let curve = Self.curve(measured) { fields["silences"] = MixMeasure.silences(curve) }
        return .object(fields)
    }

    /// `audio.mix-measure`: one stem per role, measured and read against the words. The job reports its progress
    /// and the stem and timeline second it renders; a stem that comes back without a curve, or silent although its
    /// layers hold sound, fails the job with the reason instead of completing with empty readings (B5).
    func measureMix(provider: String?, nearSeconds: Double) async throws -> JSONValue {
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        var curves: [Stem: MixMeasure.Curve] = [:]
        var loudness: [String: JSONValue] = [:]
        let stems = Stem.allCases.filter { stem in project.tracks.contains { stem.keeps($0) && !$0.items.isEmpty } }
        let reporter = JobReporter.current
        let seconds = Double(project.duration) / project.fps.value
        for (index, stem) in stems.enumerated() {
            let share = 1 / Double(stems.count), base = Double(index) * share, name = stem.rawValue
            reporter?.progress(base, detail: "Rendering the \(name) stem")
            let measured = try await measureRendered(stemProject(stem), provider: provider) { done in
                Task { @MainActor in
                    reporter?.progress(
                        base + done * share * 0.9,
                        detail: String(format: "Rendering the %@ stem at %.1f of %.1f s", name, done * seconds, seconds))
                }
            }
            let curve = Self.curve(measured)
            if let reason = MixMeasure.unreadable(stem: name, curve: curve, shouldSound: audible(stem)) {
                throw RPCFailure(-32603, reason)
            }
            curves[stem] = curve
            loudness[stem.rawValue] = .object([
                "integratedLUFS": .number(measured.integratedLUFS), "truePeakDbTP": .number(measured.truePeakDbTP),
            ])
        }
        reporter?.progress(0.95, detail: "Reading the stems against the words")
        let words = await syncWords()
        var result = MixMeasure.json(
            project, speech: curves[.speech], music: curves[.music], effects: curves[.effects],
            words: words.source == "none" ? [] : words.words, nearSeconds: nearSeconds
        ).object
        result["stems"] = .object(loudness)
        result["revision"] = .integer(project.revision)
        result["wordSource"] = .string(words.source)
        if result["musicUnderSpeech"] == .null, curves[.music] != nil {
            result["musicUnderSpeechReason"] = .string(
                curves[.speech] == nil ? "The timeline has no speech layer with sound"
                    : "Music and speech never sound at the same time")
        }
        return .object(result)
    }

    /// Whether `stem` keeps an item that should sound: media with sound (a picture's sound counted on its linked
    /// item), not muted or at −120 dB, on a layer that is not muted.
    func audible(_ stem: Stem) -> Bool {
        let sounding = Set(project.media.filter { $0.hasAudio == true && !$0.isImage }.map(\.id))
        return project.tracks.contains { track in
            stem.keeps(track) && !track.isMuted && track.items.contains { item in
                item.mediaID.map(sounding.contains) == true && item["linkedAudio"] == nil && item["muted"] != .bool(true)
                    && (item["volumeDb"]?.double ?? 0) > -100
            }
        }
    }
}
