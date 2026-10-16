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
    /// Overrides the preset's video bit rate (`export start --bitrate`, P1-F2).
    public var videoBitRate: Int?
    /// Stored transcripts of the media the edit plays, for the report's speech coverage (#507-36).
    public var transcripts: [String: SourceTranscript] = [:]
    /// Audio roles left out of this render (`export start --without music`, #520); the project's review keeps the
    /// full mix's loudness and checks.
    public var withoutRoles: Set<String> = []

    public var includesSubRip: Bool { subRip != nil }

    /// Validates the name and destination and snapshots `project`. Fails when an output file
    /// exists or one of `reserved` (outputs of queued exports) would be overwritten; the error suggests a free name.
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
        // The output's caption settings (P1-F4) choose the sidecar and what burns in; otherwise every text item
        // goes to SubRip when asked. No sidecar file when there are no captions.
        let outputCaptions = OutputPackaging.captions(source, preset: preset.argument)
        let captionText = try outputCaptions.map { $0.sidecar ? OutputPackaging.sidecar(source, captions: $0) : nil }
            ?? (includeSubRip ? SubRip.encode(source) : nil)
        let hasCaptions = captionText.map { !$0.isEmpty } ?? false
        let subRip = hasCaptions ? base.appendingPathExtension(outputCaptions?.format ?? "srt") : nil
        for url in [output, subRip].compactMap({ $0 }) where Self.isTaken(url, reserved: reserved) {
            let free = Self.availableName(
                baseName, preset: preset, directory: directory, includeSubRip: hasCaptions, reserved: reserved)
            throw ProjectError.invalid(
                "\(url.lastPathComponent) already exists or is queued; choose a new export name such as \(free)")
        }
        let dimensions = preset.dimensions(projectWidth: source.width, projectHeight: source.height)
        var sized = outputCaptions.map { OutputPackaging.burned(source, captions: $0) } ?? source
        var format = sized["format"]?.object ?? [:]
        format["width"] = .integer(dimensions.0)
        format["height"] = .integer(dimensions.1)
        sized["format"] = .object(format)
        if source.width > 0, source.height > 0 {
            sized.scaleFramingOffsets(
                x: Double(dimensions.0) / Double(source.width), y: Double(dimensions.1) / Double(source.height))
        }
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

    /// Whether an export named `name` would hit a file on disk (unless `ignoringFiles`) or an output of a queued
    /// export.
    public static func nameIsTaken(
        _ name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool, reserved: Set<URL> = [],
        ignoringFiles: Bool = false
    ) -> Bool {
        let base = directory.appendingPathComponent(name.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL
        var outputs = [base.appendingPathExtension(preset.fileExtension)]
        if includeSubRip { outputs.append(base.appendingPathExtension("srt")) }
        return outputs.contains { reserved.contains($0) || (!ignoringFiles && FileManager.default.fileExists(atPath: $0.path)) }
    }

    /// The files an earlier export named `name` left: the video and any caption sidecar.
    public static func existingOutputs(_ name: String, preset: ExportPreset, directory: URL) -> [URL] {
        let base = directory.appendingPathComponent(name.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL
        return [preset.fileExtension, "srt", "vtt"].map { base.appendingPathExtension($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// `name` when it is free, otherwise the first free `name-2`, `name-3`… (`long1-2` continues as `long1-3`; a
    /// suffix of 1000 or more, such as a year, is kept: `trip-2026` becomes `trip-2026-2`).
    public static func availableName(
        _ name: String, preset: ExportPreset, directory: URL, includeSubRip: Bool, reserved: Set<URL> = [],
        ignoringFiles: Bool = false
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        func taken(_ candidate: String) -> Bool {
            nameIsTaken(
                candidate, preset: preset, directory: directory, includeSubRip: includeSubRip, reserved: reserved,
                ignoringFiles: ignoringFiles)
        }
        guard taken(trimmed) else { return trimmed }
        var stem = trimmed
        var number = 2
        if let dash = trimmed.lastIndex(of: "-"), dash > trimmed.startIndex,
            let value = Int(trimmed[trimmed.index(after: dash)...]), (1..<1000).contains(value)
        {
            stem = String(trimmed[..<dash])
            number = value + 1
        }
        while taken("\(stem)-\(number)") { number += 1 }
        return "\(stem)-\(number)"
    }

    /// The file name of `preset`'s export when one request exports `presets` (#593): `name` alone, else
    /// `name-<preset>` (`trip-tiktok`, `trip-shorts`) so outputs that share an extension do not collide.
    public static func outputName(_ name: String, preset: ExportPreset, among presets: [ExportPreset]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.count > 1 ? "\(trimmed)-\(preset.argument)" : trimmed
    }

    /// `name` when every output of `presets` is free under it, otherwise the first free `name-2`, `name-3`…; one
    /// preset is `availableName(_:preset:…)`.
    public static func availableName(
        _ name: String, presets: [ExportPreset], directory: URL, includeSubRip: Bool, reserved: Set<URL> = []
    ) -> String {
        guard presets.count > 1 else {
            return availableName(
                name, preset: presets.first ?? .quickDraft, directory: directory, includeSubRip: includeSubRip,
                reserved: reserved)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        func free(_ base: String) -> Bool {
            presets.allSatisfy { preset in
                !nameIsTaken(
                    outputName(base, preset: preset, among: presets), preset: preset, directory: directory,
                    includeSubRip: includeSubRip, reserved: reserved)
            }
        }
        guard !free(trimmed) else { return trimmed }
        var number = 2
        while !free("\(trimmed)-\(number)") { number += 1 }
        return "\(trimmed)-\(number)"
    }

    private static func isTaken(_ url: URL, reserved: Set<URL>) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || reserved.contains(url)
    }
}
