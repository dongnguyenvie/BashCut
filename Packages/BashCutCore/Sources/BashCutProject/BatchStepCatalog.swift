import Foundation

/// The built-in steps a pipeline offers (P2-C2 "Add step", P2-C3 batch fixes): each a command or the runner's own
/// export step with starter parameters. Plugin actions are listed by the plugins themselves. Titles are English;
/// the window localizes them.
public enum BatchStepCatalog {
    public enum Group: String, Sendable, CaseIterable {
        /// Builds the edit of a new project.
        case build
        /// Fixes an existing project.
        case fix
        case check
        case export
    }

    public struct Entry: Sendable, Equatable {
        public let action: String
        public let title: String
        public let group: Group
        /// Parameters a new step starts with (the rest are the command's, `CommandCatalog.spec(named:)`); `{media}`
        /// and the other `BatchStep.variables` resolve per item. The export step without presets exports the
        /// template's outputs.
        public let params: [String: JSONValue]

        public init(_ action: String, _ title: String, _ group: Group, params: [String: JSONValue] = [:]) {
            self.action = action
            self.title = title
            self.group = group
            self.params = params
        }

        /// A new step of this kind.
        public var step: BatchStep { BatchStep(action, params: params, label: title) }
    }

    public static let entries: [Entry] = [
        Entry("media.place", "Import and place", .build, params: ["media": .string("{media}")]),
        Entry("captions.generate", "Auto captions", .build, params: ["media": .string("{media}")]),
        Entry("captions.replace", "Find and replace in captions", .fix),
        Entry("captions.style", "Caption style", .fix),
        Entry("library.apply", "Apply brand kit", .fix),
        Entry("music.replace", "Replace music", .fix, params: ["media": .string("{media}")]),
        Entry("review.run", "Review checks", .check),
        Entry("export", "Export", .export),
    ]

    public static func entry(_ action: String) -> Entry? { entries.first { $0.action == action } }
}
