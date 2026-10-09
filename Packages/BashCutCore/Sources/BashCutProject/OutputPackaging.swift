import Foundation

/// Packaging per output (P1-F3, P1-F4): chapters from section markers checked against the platform's chapter rule,
/// and how each output carries captions — burned in, a sidecar file (SRT or WebVTT), both or none — from which caption
/// layer (layers carry `language`).
public enum OutputPackaging {
    public static let captionModes = ["burn", "sidecar", "both", "none"]
    public static let captionFormats = ["srt", "vtt"]

    // MARK: Chapters

    /// `00:00 Label` lines from the section markers (a first chapter at 0 when no marker is there), with each rule of
    /// the platform's `chapters` fact and whether it holds.
    public static func chapters(_ project: Project, platform: OutputPlatform?) -> JSONValue {
        let fps = project.fps.value
        var markers = project.sectionMarkers.map { (at: $0.at, label: $0.label) }
        if markers.first?.at != 0 { markers.insert((0, "Intro"), at: 0) }
        let lengths = markers.enumerated().map { index, marker in
            Double((index + 1 < markers.count ? markers[index + 1].at : project.duration) - marker.at) / fps
        }
        let stamp = { (frame: Int) -> String in
            let seconds = Int(Double(frame) / fps)
            return seconds >= 3_600
                ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
                : String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        let lines = markers.map { "\(stamp($0.at)) \($0.label)" }
        var rules: [JSONValue] = []
        if let rule = platform?.facts["chapters"]?.value.object {
            let minCount = rule["minCount"]?.int ?? 0, minSeconds = rule["minSeconds"]?.double ?? 0
            let short = lengths.enumerated().filter { $0.element < minSeconds }.map { lines[$0.offset] }
            rules = [
                .object(["rule": .string("first at 00:00"), "holds": .bool(markers.first?.at == 0)]),
                .object(["rule": .string("at least \(minCount) chapters"), "holds": .bool(markers.count >= minCount),
                         "count": .integer(markers.count)]),
                .object(["rule": .string("each at least \(Int(minSeconds)) s"), "holds": .bool(short.isEmpty),
                         "short": .array(short.map(JSONValue.string))]),
            ]
        }
        return .object([
            "text": .string(lines.joined(separator: "\n")), "chapters": .integer(markers.count),
            "platform": platform.map { .string($0.id) } ?? .null, "rules": .array(rules),
            "holds": .bool(rules.allSatisfy { $0.object["holds"] == .bool(true) }),
        ])
    }

    // MARK: Captions

    public struct Captions: Sendable, Equatable {
        public var mode: String
        public var format: String
        /// The caption layer to use; nil: the first caption layer.
        public var track: String?
        public var burns: Bool { mode == "burn" || mode == "both" }
        public var sidecar: Bool { mode == "sidecar" || mode == "both" }
    }

    /// `output.captions[preset]`, when the project sets it.
    public static func captions(_ project: Project, preset: String) -> Captions? {
        guard let fields = project["output"]?.object["captions"]?.object[preset]?.object else { return nil }
        return Captions(
            mode: fields["mode"]?.string ?? "burn", format: fields["format"]?.string ?? "srt", track: fields["track"]?.string)
    }

    /// The project as the export renders it: caption layers other than the chosen one emptied, and the chosen one
    /// too when the output does not burn captions.
    public static func burned(_ project: Project, captions: Captions) -> Project {
        var copy = project
        let chosen = captions.track ?? project.tracks.first { $0.role == TrackRole.captions }?.id
        for index in copy.tracks.indices where copy.tracks[index].role == TrackRole.captions {
            if !captions.burns || copy.tracks[index].id != chosen { copy.tracks[index].items = [] }
        }
        return copy
    }

    /// The chosen caption layer as SubRip or WebVTT text; nil when it has no cues.
    public static func sidecar(_ project: Project, captions: Captions) -> String? {
        let chosen = captions.track ?? project.tracks.first { $0.role == TrackRole.captions }?.id
        let cues = (project.tracks.first { $0.id == chosen }?.items ?? [])
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.at < $1.at }
        guard !cues.isEmpty else { return nil }
        let fps = project.fps.value
        let stamp = { (frame: Int, separator: String) -> String in
            let total = Int((Double(frame) / fps * 1_000).rounded())
            return String(format: "%02d:%02d:%02d%@%03d", total / 3_600_000, total / 60_000 % 60, total / 1_000 % 60, separator, total % 1_000)
        }
        let vtt = captions.format == "vtt"
        let body = cues.enumerated().map { index, cue in
            let separator = vtt ? "." : ","
            let text = cue.text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            return "\(index + 1)\n\(stamp(cue.at, separator)) --> \(stamp(max(cue.end, cue.at + 1), separator))\n\(text)\n"
        }.joined(separator: "\n")
        return vtt ? "WEBVTT\n\n" + body : body
    }
}

extension Project {
    /// `output.captions`: preset → {mode, format, track}; caption layers' `language` as a short tag.
    func validateOutputCaptions() throws {
        if let value = self["output"]?.object["captions"], value != .null {
            guard case .object(let map) = value, map.keys.allSatisfy(OutputPresetName.all.contains) else {
                throw ProjectError.invalid("output.captions: preset → {mode, format, track}")
            }
            for (preset, entry) in map {
                let fields = entry.object
                guard fields["mode"].map({ $0.string.map(OutputPackaging.captionModes.contains) == true }) ?? true,
                    fields["format"].map({ $0.string.map(OutputPackaging.captionFormats.contains) == true }) ?? true,
                    fields["track"].map({ id in tracks.contains { $0.id == id.string && $0.role == TrackRole.captions } }) ?? true
                else {
                    throw ProjectError.invalid(
                        "output.captions.\(preset): mode burn|sidecar|both|none, format srt|vtt, track a caption layer")
                }
            }
        }
        for track in tracks where track["language"] != nil {
            guard let tag = track["language"]?.string, (1...35).contains(tag.count) else {
                throw ProjectError.invalid("Layer \(track.id): language must be a short tag such as vi or en")
            }
        }
    }
}
