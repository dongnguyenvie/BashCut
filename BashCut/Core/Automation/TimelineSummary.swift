import BashCutProject
import Foundation

/// What `timeline get` returns: the layers with their items, plus everything else an agent needs to check its
/// own edits (transitions, sections and other markers, LUTs).
public enum TimelineSummary {
    public static func json(_ project: Project) -> JSONValue {
        .object([
            "rev": .integer(project.revision), "format": project["format"] ?? .null,
            "tracks": tracks(project),
            "transitions": .array(project.transitions.map { .object($0.fields) }),
            "markers": .array(project.markers.map { .object($0.fields) }),
            "luts": .array(project.colorLUTs.map { .object($0.fields) }),
            "scale": ReviewScale.all(project),
            "media": .array(project.media.map(rights)),
        ])
    }

    /// The stored layers, each with its short display label (`V1`, `A1`, #531) added as `label`.
    static func tracks(_ project: Project) -> JSONValue {
        let labels = project.trackLabels
        guard case .array(let rows) = project["tracks"] ?? .array([]) else { return .array([]) }
        return .array(rows.map { row in
            guard case .object(var fields) = row, let id = fields["id"]?.string, let label = labels[id] else { return row }
            fields["label"] = .string(label)
            return .object(fields)
        })
    }

    /// Each media's path, kind, licence and provenance as stored (P2-H8); null when not recorded.
    static func rights(_ media: Media) -> JSONValue {
        .object([
            "id": .string(media.id), "path": .string(media.path), "kind": .string(media.kind),
            "license": media["license"] ?? .null,
            "provenance": media["provenance"] ?? .null,
        ])
    }

    public static func text(_ project: Project) -> String {
        var lines = [
            "project \(project.name) rev \(project.revision) \(project.width)x\(project.height) \(project.fps.value)fps"
        ]
        let labels = project.trackLabels
        for track in project.tracks {
            let layer = "\(labels[track.id] ?? track.id) \(track.role.uppercased())"
            for item in track.items.sorted(by: { $0.at < $1.at }) {
                let media = item.mediaID ?? (track.isAdjustment ? "adjustment" : "text")
                lines.append(
                    "\(layer) \(item.id) \(item.at)-\(item.end) media=\(media) in=\(item.sourceIn) \(item.text)"
                )
            }
        }
        for transition in project.transitions {
            lines.append(
                "TRANSITION \(transition.id) \(transition.kind) \(transition.fromItemID)->\(transition.toItemID) "
                    + "dur=\(transition.duration)"
                    + (transition.easing == TimelineTransition.defaultEasing ? "" : " easing=\(transition.easing)"))
        }
        for marker in project.markers.sorted(by: { $0.at < $1.at }) {
            lines.append("MARKER \(marker.id) \(marker.kind) at=\(marker.at) \(marker.label)")
        }
        return lines.joined(separator: "\n")
    }
}
