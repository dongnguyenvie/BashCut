import Foundation

/// Saved pipelines (`batch presets`), one JSON file each in the user store,
/// `~/Library/Application Support/BashCut/Batch/Presets`, beside the user library. A preset is a pipeline usually
/// saved without inputs: `batch run --preset NAME --inputs …` adds them.
public struct BatchPresetStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// The user store under an Application Support folder.
    public static func user(applicationSupport: URL) -> BatchPresetStore {
        BatchPresetStore(root: applicationSupport.appendingPathComponent("BashCut/Batch/Presets", isDirectory: true))
    }

    /// The file name of a preset name: lowercase letters, digits and dashes.
    public static func slug(_ name: String) -> String {
        let folded = name.searchFolded
        var slug = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        return String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(80))
    }

    private func file(_ name: String) throws -> URL {
        let slug = Self.slug(name)
        guard !slug.isEmpty else { throw ProjectError.invalid(BatchMessages.presetNameLetters) }
        return root.appendingPathComponent(slug).appendingPathExtension("json")
    }

    /// Every saved preset, by name; a file that does not read is skipped.
    public func list() -> [BatchPipeline] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? load(file: $0) }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }

    public func load(_ name: String) throws -> BatchPipeline {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let names = list().compactMap(\.name)
            throw ProjectError.invalid(names.isEmpty
                ? BatchMessages.text(BatchMessages.noPreset, name)
                : BatchMessages.text(BatchMessages.noPresetSaved, name, names.joined(separator: ", ")))
        }
        return try load(file: url)
    }

    private func load(file url: URL) throws -> BatchPipeline {
        try BatchPipeline(json: JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }

    /// Saves `pipeline` under its name (replacing a preset of that name) and returns the file.
    @discardableResult
    public func save(_ pipeline: BatchPipeline) throws -> URL {
        guard let name = pipeline.name else { throw ProjectError.invalid(BatchMessages.presetName) }
        guard !pipeline.steps.isEmpty else { throw ProjectError.invalid(BatchMessages.presetSteps) }
        let url = try file(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pipeline).write(to: url, options: .atomic)
        return url
    }

    /// Removes the preset; false when there was none.
    @discardableResult
    public func remove(_ name: String) throws -> Bool {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }
}
