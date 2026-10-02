import Foundation

/// Upgrades project files written by older schemas when they are opened. Changing the format means:
/// bump `Project.schema`, append a step from the previous version here, describe the field in
/// `ProjectSchema`/`ItemProperty`, regenerate docs/reference/project.schema.json (`scripts/update-schema.sh`)
/// and add a migration test. A file with an unknown schema is left as is and fails validation.
public enum ProjectMigration {
    public struct Step: Sendable {
        public let from: String
        public let to: String
        public let apply: @Sendable (inout Project) throws -> Void
    }

    /// Ordered upgrade steps. Empty while `bashcut.project/1` is the only schema.
    public static let steps: [Step] = []

    /// Applies steps until the project reaches `Project.schema` or no step matches.
    public static func upgrade(_ project: inout Project) throws {
        var applied = 0
        while let schema = project["schema"]?.string, schema != Project.schema,
            let step = steps.first(where: { $0.from == schema })
        {
            try step.apply(&project)
            project["schema"] = .string(step.to)
            applied += 1
            guard applied <= steps.count else { throw ProjectError.invalid("schema: migration loop") }
        }
    }
}
