import Foundation

/// Writes a whole project in another timeline format (OpenTimelineIO, SubRip captions, …). A new format
/// is one conforming type plus an entry in the app's format registry.
public protocol TimelineExporter: Sendable {
    /// Stable ID for automation and settings, e.g. "otio".
    var id: String { get }
    var title: String { get }
    var fileExtension: String { get }
    func data(for project: Project) throws -> Data
}

/// Turns a file in another timeline format into a new project.
public protocol TimelineImporter: Sendable {
    var id: String { get }
    var title: String { get }
    var fileExtensions: [String] { get }
    /// `destinationDirectory` is where the new project file will live; media paths are made relative to it.
    func importTimeline(_ data: Data, name: String, destinationDirectory: URL) throws -> TimelineImport
}

/// A new project from an import, with what the source contained next to what the project got.
/// `title`, `sourceName`, count labels and `mismatchNote` are English UI keys the app localizes.
public struct TimelineImport: Sendable, Equatable {
    public struct Count: Sendable, Equatable {
        /// Machine name for automation results, e.g. "cuts".
        public let key: String
        public let label: String
        /// Nil when the source does not state it.
        public let source: Int?
        public let imported: Int

        public init(key: String, label: String, source: Int?, imported: Int) {
            self.key = key
            self.label = label
            self.source = source
            self.imported = imported
        }
    }

    public let project: Project
    public let title: String
    public let sourceName: String
    public let counts: [Count]
    /// Shown when a total the source states does not match the import.
    public let mismatchNote: String?
    /// Things a person should check by hand.
    public let warnings: [String]

    /// `{key: imported, sourceKey: source, warnings}`, the shape automation results use.
    public var json: JSONValue {
        var values: [String: JSONValue] = ["warnings": .array(warnings.map(JSONValue.string))]
        for count in counts {
            values[count.key] = .integer(count.imported)
            if let source = count.source {
                values["source" + count.key.prefix(1).uppercased() + count.key.dropFirst()] = .integer(source)
            }
        }
        return .object(values)
    }

    public init(
        project: Project, title: String, sourceName: String, counts: [Count], mismatchNote: String? = nil,
        warnings: [String] = []
    ) {
        self.project = project
        self.title = title
        self.sourceName = sourceName
        self.counts = counts
        self.mismatchNote = mismatchNote
        self.warnings = warnings
    }
}

/// SubRip captions of the project's caption layers.
public struct SubRipExporter: TimelineExporter {
    public let id = "srt"
    public let title = "SubRip captions"
    public let fileExtension = "srt"

    public init() {}

    public func data(for project: Project) throws -> Data { Data(try SubRip.encode(project).utf8) }
}
