import BashCutProject
import Foundation

extension CommandCatalog {
    static let baseRevision = CommandParameter(
        "baseRev", .integer,
        "Current project revision (rev of context.get or of your last edit), or \"last\": the revision as of your "
            + "session's last command, still stale when anyone else changed the project since",
        required: true, minimum: 0, cli: .option("base-rev"))
    /// The `baseRev` value that stands for the revision the caller last saw.
    public static let lastRevision = "last"
}
