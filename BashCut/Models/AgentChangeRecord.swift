import BashCutProject
import Foundation

struct AgentChangeRecord: Identifiable {
    let id = UUID()
    let author: Author
    let label: String
    let beforeRevision: Int
    let afterRevision: Int
    let changes: [ProjectItemChange]
    /// The command that made it, when it came from one (P3-I1).
    var command: String?

    var changedIDs: Set<String> { Set(changes.map(\.itemID)) }
}
