import BashCutProject
import Foundation

/// A blocking step a plugin runs before a final export (plugin API 12, #634): e.g. HyperFrames renders its draft
/// graphics again at full quality. BashCut runs `command` (a file inside the plugin) when `when` holds for the project,
/// with the plugin's environment plus a short-lived automation token, streams its `::progress` lines, lets the user
/// cancel it, then exports the project as the step left it. The step changes the project through the `bashcut` CLI
/// (`BASHCUT_CLI`), normally one `timeline apply`, so the change is one undo step.
public struct PluginExportStepContribution: Codable, Sendable, Equatable, Identifiable {
    public static let maximumSteps = 8
    public static let defaultTimeoutSeconds = 1800

    public let id: String
    public let title: LocalizedText
    /// A file inside the plugin and its arguments; never a shell string or a tool on PATH.
    public let command: PluginCommand
    /// When the step is needed: `media.data.<path>` holds for a media file a timeline item uses
    /// (`PluginExportStepCondition`).
    public let when: String
    /// The step fails after this long (60…7200 s, default 1800).
    public let timeoutSeconds: Int?

    public init(id: String, title: LocalizedText, command: PluginCommand, when: String, timeoutSeconds: Int? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.when = when
        self.timeoutSeconds = timeoutSeconds
    }

    public var condition: PluginExportStepCondition? { try? PluginExportStepCondition(parsing: when) }
    public var timeout: TimeInterval { TimeInterval(timeoutSeconds ?? Self.defaultTimeoutSeconds) }

    /// Whether the export of `project` needs this step now.
    public func matches(_ project: Project) -> Bool { condition?.holds(for: project) ?? false }

    func validate() throws {
        guard PluginIdentifier.isKey(id) else { throw PluginError.invalid("Export step id \(id) must be a lowercase key") }
        guard title.isValid(limit: 60) else {
            throw PluginError.invalid("Export step \(id) needs a title of at most 60 characters per language, English included")
        }
        guard command.executable.contains("/"), command.arguments.count <= 64, (try? command.validate()) != nil else {
            throw PluginError.invalid("Export step \(id) must run a file inside the plugin bundle (bin/…)")
        }
        _ = try PluginExportStepCondition(parsing: when)
        if let timeoutSeconds, !(60...7200).contains(timeoutSeconds) {
            throw PluginError.invalid("Export step \(id) timeoutSeconds must be 60...7200")
        }
    }
}

/// An export step's `when`: `media.data.<key>[.<key>…]`, true when a media file at least one timeline item uses has
/// a truthy value there (true, a non-zero number, a non-empty string, list or object). Media no item uses and media
/// without that data never count.
public struct PluginExportStepCondition: Sendable, Equatable {
    public let path: [String]

    public init(parsing text: String) throws {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard text.count <= 200, parts.count >= 3, parts[0] == "media", parts[1] == "data",
            parts.dropFirst(2).allSatisfy(PluginIdentifier.isKey)
        else {
            throw PluginError.invalid("Export step when must be media.data.<key>[.<key>…], e.g. media.data.graphics.draft")
        }
        path = Array(parts.dropFirst(2))
    }

    /// The media the condition holds for, among those a timeline item uses, in media order.
    public func matchingMedia(_ project: Project) -> [String] {
        let used = Set(project.tracks.flatMap(\.items).compactMap(\.mediaID))
        return project.media.filter { used.contains($0.id) && Self.truthy(value(in: $0.fields["data"])) }.map(\.id)
    }

    public func holds(for project: Project) -> Bool { !matchingMedia(project).isEmpty }

    private func value(in data: JSONValue?) -> JSONValue? {
        path.reduce(data) { value, key in value?.object[key] }
    }

    static func truthy(_ value: JSONValue?) -> Bool {
        switch value {
        case .bool(let flag): flag
        case .integer(let number): number != 0
        case .number(let number): number != 0
        case .string(let text): !text.isEmpty
        case .array(let list): !list.isEmpty
        case .object(let fields): !fields.isEmpty
        default: false
        }
    }
}

extension PluginManifest {
    /// Steps the plugin runs before a final export (API 12).
    public var exportSteps: [PluginExportStepContribution] { contributes?.exportSteps ?? [] }

    func validateExportSteps() throws {
        guard !exportSteps.isEmpty else { return }
        guard apiVersion >= 12 else { throw PluginError.invalid("contributes.exportSteps needs apiVersion 12") }
        guard exportSteps.count <= PluginExportStepContribution.maximumSteps,
            Set(exportSteps.map(\.id)).count == exportSteps.count
        else {
            throw PluginError.invalid(
                "contributes.exportSteps lists at most \(PluginExportStepContribution.maximumSteps) steps with unique ids")
        }
        for step in exportSteps { try step.validate() }
    }
}
