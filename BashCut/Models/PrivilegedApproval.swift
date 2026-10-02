import BashCutProject
import Foundation

struct ApprovalArgument: Identifiable, Sendable {
    let name: String
    let value: String
    var id: String { name }
}

struct PrivilegedApprovalPrompt: Identifiable, Sendable {
    let id: UUID
    let method: String
    let author: Author
    let arguments: [ApprovalArgument]
}
