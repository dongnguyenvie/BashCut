import BashCutProject
import Foundation

struct AgentChangeRecord: Identifiable {
    let id = UUID()
    let author: Author
    let label: String
    let beforeRevision: Int
    let afterRevision: Int
    let changes: [ProjectItemChange]

    var changedIDs: Set<String> { Set(changes.map(\.itemID)) }
}
