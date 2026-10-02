import AppKit
import BashCutAutomation
import BashCutProject
import Foundation

extension ProjectDocument {
    func queuePrivilegedApproval(
        method: String, author: Author, arguments: [String: String],
        action: @escaping @MainActor () throws -> Void
    ) throws -> UUID {
        guard privilegedApproval == nil else {
            throw RPCFailure(-32003, "Another privileged action is awaiting approval")
        }
        let id = UUID()
        privilegedAction = action
        privilegedApproval = PrivilegedApprovalPrompt(
            id: id, method: method, author: author,
            arguments: arguments.sorted { $0.key < $1.key }.map {
                ApprovalArgument(name: $0.key, value: String($0.value.prefix(1_000)))
            })
        NSApp.activate(ignoringOtherApps: true)
        return id
    }

    func resolvePrivilegedApproval(_ approved: Bool) {
        let prompt = privilegedApproval
        let action = privilegedAction
        privilegedApproval = nil
        privilegedAction = nil
        if let prompt {
            registry.recordApproval(method: prompt.method, author: prompt.author, approved: approved)
        }
        guard approved else {
            if let prompt {
                message = String(localized: "Denied \(prompt.method) from \(prompt.author.rawValue.capitalized)")
            }
            return
        }
        do {
            try action?()
        } catch {
            message = error.localizedDescription
        }
    }
}
