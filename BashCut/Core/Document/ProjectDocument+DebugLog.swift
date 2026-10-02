import BashCutAutomation
import BashCutProject
import Foundation

/// Debug-log helpers; see `DebugLog` for where lines go.
extension ProjectDocument {
    /// Layers in stored order with item counts, e.g. `v1 video/main×3 | a1 audio/dialogue×3`.
    func layoutSummary(_ project: Project? = nil) -> String {
        let project = project ?? self.project
        return project.tracks.map { "\($0.id) \($0.kind)/\($0.role)×\($0.items.count)" }.joined(separator: " | ")
    }

    func mediaSummary(_ media: Media) -> String {
        "\(media.id.prefix(8)) kind=\(media.kind) hasAudio=\(media.hasAudio.map(String.init) ?? "nil") "
            + "frames=\(media.frames) fps=\(media.fps.value) path=\(media.path)"
    }

    static func describe(_ operation: EditOperation) -> String {
        if case .restore = operation { return "restore(snapshot)" }
        guard let data = try? JSONEncoder().encode(operation.json), let text = String(data: data, encoding: .utf8)
        else { return "\(operation)" }
        return text.count > 600 ? text.prefix(600) + "…(\(text.count) chars)" : text
    }

    /// Logs a freshly opened project, including whether layer rules repaired it on load.
    func logOpened(_ url: URL, data: Data?) {
        var line = "opened \(url.path) rev=\(project.revision) layers: \(layoutSummary())"
        if let data, let raw = try? JSONDecoder().decode(Project.self, from: data), raw.tracks != project.tracks {
            line += " — REPAIRED by layer rules; on disk: \(layoutSummary(raw))"
        }
        DebugLog.write("project", line)
        for media in project.media { DebugLog.write("project", "media \(mediaSummary(media))") }
    }
}
