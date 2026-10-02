import BashCutEngine
import BashCutProject
import Foundation

/// A validated export: the project as it was when requested, the destination files and options.
/// Later edits do not change a queued export.
public struct ExportRequest: Sendable {
    /// The project as edited, used for metrics and loudness write-back.
    public let source: Project
    /// `source` with the preset's output size.
    public let project: Project
    public let root: URL
    public let workspace: URL?
    public let output: URL
    public let subRip: URL?
    public let captionText: String?
    public let preset: ExportPreset
    public let normalizeAudio: Bool

    public var includesSubRip: Bool { subRip != nil }

    /// Validates the name and destination and snapshots `project`. Fails when an output file
    /// exists or one of `reserved` (outputs of queued exports) would be overwritten.
    public init(
        project source: Project, root: URL, workspace: URL?, name: String, preset: ExportPreset,
        directory: URL, includeSubRip: Bool, normalizeAudio: Bool, reserved: Set<URL> = []
    ) throws {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty, !baseName.contains("/"), !baseName.contains(":"), baseName.count <= 180 else {
            throw ProjectError.invalid("Use a file name without slashes or colons")
        }
        guard source.duration > 0 else { throw ProjectError.invalid("The timeline is empty") }
        let base = directory.appendingPathComponent(baseName).standardizedFileURL
        let output = base.appendingPathExtension(preset.fileExtension)
        // No SubRip file when the timeline has no captions.
        let captionText = includeSubRip ? try SubRip.encode(source) : nil
        let hasCaptions = captionText.map { !$0.isEmpty } ?? false
        let subRip = hasCaptions ? base.appendingPathExtension("srt") : nil
        for url in [output, subRip].compactMap({ $0 }) {
            guard !FileManager.default.fileExists(atPath: url.path), !reserved.contains(url) else {
                throw ProjectError.invalid("Choose a new export name; an output already exists or is queued")
            }
        }
        let dimensions = preset.dimensions(projectWidth: source.width, projectHeight: source.height)
        var sized = source
        var format = sized["format"]?.object ?? [:]
        format["width"] = .integer(dimensions.0)
        format["height"] = .integer(dimensions.1)
        sized["format"] = .object(format)
        self.source = source
        project = sized
        self.root = root
        self.workspace = workspace
        self.output = output
        self.subRip = subRip
        self.captionText = hasCaptions ? captionText : nil
        self.preset = preset
        self.normalizeAudio = normalizeAudio
    }

    /// Files this export will write, for duplicate checks against the queue.
    public var outputs: Set<URL> { Set([output, subRip].compactMap { $0 }) }
}
