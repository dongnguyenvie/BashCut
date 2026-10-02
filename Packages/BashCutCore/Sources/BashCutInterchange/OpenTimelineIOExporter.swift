import BashCutProject
import Foundation

/// OpenTimelineIO JSON: one OTIO track per layer lane, clips referencing the original media.
public struct OpenTimelineIOExporter: TimelineExporter {
    public let id = "otio"
    public let title = "OpenTimelineIO"
    public let fileExtension = "otio"

    public init() {}

    public func data(for project: Project) throws -> Data { try Self.data(for: project) }

    public static func data(for project: Project) throws -> Data {
        try project.validate()
        let rate = project.fps.value
        let tracks = project.tracks.flatMap { track in
            lanes(for: track.items).enumerated().map { lane, items in
                trackJSON(track, lane: lane, items: items, project: project, rate: rate)
            }
        }
        let root: JSONValue = .object([
            "OTIO_SCHEMA": .string("Timeline.1"),
            "name": .string(project.name),
            "global_start_time": .null,
            "metadata": .object([
                "bashcut": .object([
                    "projectID": project["id"] ?? .null,
                    "schema": project["schema"] ?? .null,
                    "format": project["format"] ?? .null,
                    "transitions": project["transitions"] ?? .array([]),
                ]),
            ]),
            "tracks": .object([
                "OTIO_SCHEMA": .string("Stack.1"), "name": .string("BashCut Timeline"),
                "metadata": .object([:]), "effects": .array([]),
                "markers": .array(project.markers.map { marker($0, rate: rate) }),
                "enabled": .bool(true), "source_range": .null, "children": .array(tracks),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(root)
    }
}

private extension OpenTimelineIOExporter {
    static func lanes(for items: [Item]) -> [[Item]] {
        var result: [[Item]] = []
        for item in items.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            if let index = result.firstIndex(where: { ($0.last?.end ?? 0) <= item.at }) {
                result[index].append(item)
            } else {
                result.append([item])
            }
        }
        return result.isEmpty ? [[]] : result
    }

    static func trackJSON(
        _ track: Track, lane: Int, items: [Item], project: Project, rate: Double
    ) -> JSONValue {
        var children: [JSONValue] = []
        var cursor = 0
        for item in items {
            if item.at > cursor { children.append(gap(duration: item.at - cursor, rate: rate)) }
            children.append(clip(item, project: project, rate: rate))
            cursor = item.end
        }
        var trackFields = track.fields
        trackFields.removeValue(forKey: "items")
        return .object([
            "OTIO_SCHEMA": .string("Track.1"),
            "name": .string(lane == 0 ? track.name : "\(track.name) \(lane + 1)"),
            "kind": .string(track.kind == "audio" ? "Audio" : "Video"),
            "metadata": .object([
                "bashcut": .object([
                    "trackID": .string(track.id), "role": .string(track.role),
                    "lane": .integer(lane), "fields": .object(trackFields),
                ]),
            ]),
            "effects": .array([]), "markers": .array([]), "children": .array(children),
            "enabled": .bool(true), "source_range": .null,
        ])
    }

    static func gap(duration: Int, rate: Double) -> JSONValue {
        .object([
            "OTIO_SCHEMA": .string("Gap.1"), "name": .string(""),
            "metadata": .object([:]), "effects": .array([]), "markers": .array([]),
            "enabled": .bool(true),
            "source_range": timeRange(start: 0, duration: duration, rate: rate),
        ])
    }

    static func clip(_ item: Item, project: Project, rate: Double) -> JSONValue {
        let media = project.media.first { $0.id == item.mediaID }
        let reference: JSONValue
        if let media {
            reference = .object([
                "OTIO_SCHEMA": .string("ExternalReference.1"),
                "name": .string(URL(fileURLWithPath: media.path).lastPathComponent),
                "target_url": .string(media.path), "metadata": .object([:]),
                "available_range": .null,
            ])
        } else if item.fields["text"] == nil {
            reference = .object([
                "OTIO_SCHEMA": .string("GeneratorReference.1"), "name": .string("Adjustment"),
                "generator_kind": .string("Adjustment"), "parameters": .object(["color": item["color"] ?? .object([:])]),
                "metadata": .object([:]), "available_range": .null,
            ])
        } else {
            reference = .object([
                "OTIO_SCHEMA": .string("GeneratorReference.1"), "name": .string("Text"),
                "generator_kind": .string("Text"),
                "parameters": .object(["text": .string(item.text)]),
                "metadata": .object([:]), "available_range": .null,
            ])
        }
        let sourceRate = media?.fps.value ?? rate
        var effects: [JSONValue] = []
        if item.speed != 1 {
            effects.append(.object([
                "OTIO_SCHEMA": .string("LinearTimeWarp.1"), "name": .string("Speed"),
                "effect_name": .string("LinearTimeWarp"), "time_scalar": .number(item.speed),
                "metadata": .object([:]), "enabled": .bool(true),
            ]))
        }
        return .object([
            "OTIO_SCHEMA": .string("Clip.1"), "name": .string(item.text.isEmpty ? item.id : item.text),
            "metadata": .object(["bashcut": .object(["itemID": .string(item.id), "fields": .object(item.fields)])]),
            "media_reference": reference, "effects": .array(effects), "markers": .array([]),
            "enabled": .bool(true),
            "source_range": .object([
                "OTIO_SCHEMA": .string("TimeRange.1"),
                "start_time": rationalTime(value: item.sourceIn, rate: sourceRate),
                "duration": rationalTime(value: item.duration, rate: rate),
            ]),
        ])
    }

    static func timeRange(start: Int, duration: Int, rate: Double) -> JSONValue {
        .object([
            "OTIO_SCHEMA": .string("TimeRange.1"),
            "start_time": rationalTime(value: start, rate: rate),
            "duration": rationalTime(value: duration, rate: rate),
        ])
    }

    static func rationalTime(value: Int, rate: Double) -> JSONValue {
        .object([
            "OTIO_SCHEMA": .string("RationalTime.1"),
            "value": .number(Double(value)), "rate": .number(rate),
        ])
    }

    static func marker(_ marker: TimelineMarker, rate: Double) -> JSONValue {
        .object([
            "OTIO_SCHEMA": .string("Marker.2"), "name": .string(marker.label),
            "color": .string("BLUE"),
            "marked_range": timeRange(start: marker.at, duration: 0, rate: rate),
            "metadata": .object(["bashcut": .object(["fields": .object(marker.fields)])]),
        ])
    }
}
