import BashCutImport
import BashCutInterchange
import BashCutProject
import Foundation

/// The timeline formats BashCut can write and read. Adding a format means adding its exporter or
/// importer here.
public enum TimelineFormats {
    public static let exporters: [any TimelineExporter] = [OpenTimelineIOExporter(), SubRipExporter()]
    public static let importers: [any TimelineImporter] = [LegacyEDLFormat()]

    public static func exporter(_ id: String) -> (any TimelineExporter)? { exporters.first { $0.id == id } }
    public static func importer(_ id: String) -> (any TimelineImporter)? { importers.first { $0.id == id } }

    /// Writes `project` with `exporter`, refusing to replace a file unless `allowReplace`.
    public static func write(
        _ project: Project, with exporter: any TimelineExporter, to url: URL, allowReplace: Bool = false
    ) throws {
        guard allowReplace || !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Choose a new export name; an output already exists")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try exporter.data(for: project).write(to: url, options: .atomic)
    }
}
