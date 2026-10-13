import Foundation

/// What an edit looks like in a few numbers (P3-I2), kept with every finished export and compared across projects by
/// `project history`: the look, caption and title presets, music, transitions, the cut rhythm on Main, the hook (the
/// first seconds) and the sections. Measured facts only; what counts as "the same again" is the skill's call.
public enum ProjectFingerprint {
    /// Seconds from the start that count as the hook.
    public static let hookSeconds = 3.0

    public struct Section: Sendable, Equatable {
        public let label: String
        public let start: Double
        public let end: Double

        public init(label: String, start: Double, end: Double) {
            self.label = label
            self.start = start
            self.end = end
        }
    }

    public struct Word: Sendable, Equatable {
        public let text: String
        public let start: Double
        public let end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// The section markers as spans in seconds: each runs to the next marker or the end of the timeline.
    public static func sections(_ project: Project) -> [Section] {
        let fps = project.fps.value
        let markers = project.sectionMarkers.filter { $0.at >= 0 }
        let end = Double(project.duration) / fps
        return markers.enumerated().map { index, marker in
            let next = index + 1 < markers.count ? Double(markers[index + 1].at) / fps : end
            return Section(label: marker.label, start: rounded(Double(marker.at) / fps), end: rounded(max(next, Double(marker.at) / fps)))
        }
    }

    /// The words on the caption layers in timeline seconds, in order.
    public static func words(_ project: Project) -> [Word] {
        TimelineTranscript.wordsJSON(project).object["words"]?.array.compactMap { row in
            let fields = row.object
            guard let text = fields["text"]?.string, let start = fields["atSeconds"]?.double,
                let end = fields["endSeconds"]?.double
            else { return nil }
            return Word(text: text, start: start, end: end)
        } ?? []
    }

    public static func json(_ project: Project) -> JSONValue {
        let fps = project.fps.value
        let seconds = { (frames: Int) in rounded(Double(frames) / fps) }
        let tracks = project.tracks
        let main = tracks.filter { $0.role == TrackRole.main }.flatMap(\.items).sorted { $0.at < $1.at }
        let lengths = main.map { Double($0.duration) / fps }.sorted()
        let mediaName = { (id: String?) -> String? in
            id.flatMap { id in project.media.first { $0.id == id } }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        }
        let lutNames = Dictionary(project.colorLUTs.map { lut in
            (lut.id, lut.fields[ColorLUT.libraryItemField]?.string ?? lut.name)
        }, uniquingKeysWith: { first, _ in first })
        let looks = distinct(tracks.filter { $0.kind == TrackKind.video || $0.kind == TrackKind.adjustment }
            .flatMap(\.items).compactMap { $0["color"]?.object["lut"]?.string.flatMap { lutNames[$0] } })
        let presets = { (role: String) in
            distinct(tracks.filter { $0.role == role }.flatMap(\.items).compactMap(\.textPreset))
        }
        let music = distinct(tracks.filter { $0.role == TrackRole.music }.flatMap(\.items).compactMap { mediaName($0.mediaID) })
        var transitions: [String: Int] = [:]
        for transition in project.transitions where !transition.kind.isEmpty { transitions[transition.kind, default: 0] += 1 }
        let texts = tracks.filter { $0.kind == TrackKind.text }.flatMap(\.items)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.at < $1.at }
        let hookWords = words(project).filter { $0.start < hookSeconds }.map(\.text)
        var hook: [String: JSONValue] = [
            "firstCutSeconds": main.first.map { .number(seconds($0.end)) } ?? .null,
            "firstTextSeconds": texts.first.map { .number(seconds($0.at)) } ?? .null,
            "firstText": texts.first.map { .string(String(oneLine($0.text).prefix(80))) } ?? .null,
            "firstMedia": mediaName(main.first?.mediaID).map(JSONValue.string) ?? .null,
            "cutsInHook": .integer(main.filter { Double($0.end) / fps < hookSeconds && $0.end < project.duration }.count),
        ]
        hook["words"] = hookWords.isEmpty ? .null : .string(String(hookWords.joined(separator: " ").prefix(160)))
        return .object([
            "rev": .integer(project.revision), "seconds": .number(seconds(project.duration)),
            "clips": .integer(main.count),
            "averageCutSeconds": lengths.isEmpty ? .null : .number(rounded(lengths.reduce(0, +) / Double(lengths.count))),
            "medianCutSeconds": lengths.isEmpty ? .null : .number(rounded(lengths[lengths.count / 2])),
            "transitions": .object(transitions.mapValues(JSONValue.integer)),
            "looks": .array(looks.map(JSONValue.string)),
            "captionPresets": .array(presets(TrackRole.captions).map(JSONValue.string)),
            "titlePresets": .array(presets(TrackRole.titles).map(JSONValue.string)),
            "music": .array(music.map(JSONValue.string)),
            "hook": .object(hook),
            "sections": .array(sections(project).map { section in
                .object(["label": .string(section.label), "start": .number(section.start), "end": .number(section.end)])
            }),
        ])
    }

    static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
