import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// An agent session that can carry an attached scope: a chat tab or a terminal tab (#356).
@MainActor protocol AgentScopeOwner: AnyObject {
    /// The items attached with Send to Agent.
    var scope: [AgentScopeItem] { get }
    /// The user chose Allow for this request: edits outside the scope run until the request ends.
    var scopeAllowed: Bool { get set }
    /// Items made by in-scope edits (a split's second half, a title inside the span); they count as in scope.
    var scopeExtra: Set<String> { get set }
    /// The answer to the last held edit, for `context get` (`scope.last`).
    var scopeLast: JSONValue? { get set }
    /// The tab's title, for the dialog.
    var title: String { get }
}

/// An agent edit outside its attached scope, waiting for the user (#356).
struct AgentScopeHold: Identifiable {
    let id: UUID
    let operation: EditOperation
    let label: String
    let author: Author
    let coalescingKey: String?
    /// The session that made it.
    let token: String
    /// The tab's title and what lies outside the scope, for the sheet.
    let agent: String
    let outside: String
}

/// The buttons of the held-edit sheet; the raw values are the `ui respond` option IDs.
enum AgentScopeChoice: String {
    case reject
    case allowOnce = "allow-once"
    case allowRequest = "allow-request"
}

/// What the guard decided for one edit; `owner` is set while a scope is active.
struct AgentScopeDecision {
    var owner: (any AgentScopeOwner)?
    /// The edit stayed inside the scope, so items it makes join the scope.
    var inScope = false
}

extension ProjectDocument {
    /// The guard's mode; off while all agent actions are allowed.
    var agentScopeMode: AgentScopeMode {
        settings.dangerouslyAllowAgents ? .off : AgentScopeMode(rawValue: settings.agentScopeModeRaw) ?? .ask
    }

    /// The chat or terminal tab a live session token belongs to.
    func scopeOwner(for token: String) -> (any AgentScopeOwner)? {
        if let chat = chatAgents.owner(of: token) { return chat }
        return agents.sessions.first { $0.token == token }
    }

    /// The scope guard (#356), called by the edit choke point before an edit applies. Edits by the user (also from
    /// a shell tab), by sessions without an attached scope, and every edit while the guard is off pass. Otherwise
    /// an edit outside the scope is rejected (block) or held while the user is asked (ask). Asking never blocks the
    /// main actor: the command fails at once with `held` in its data, and the edit applies later if the user allows
    /// it. Only the user can allow it.
    func checkAgentScope(
        _ operation: EditOperation, label: String, author: Author, coalescingKey: String?
    ) throws -> AgentScopeDecision {
        guard author != .user, let token = CommandCaller.token, let owner = scopeOwner(for: token),
            !owner.scope.isEmpty
        else { return AgentScopeDecision() }
        let mode = agentScopeMode
        guard mode != .off, !owner.scopeAllowed else { return AgentScopeDecision(owner: owner) }
        let check = AgentScopeGuard.check(operation, scope: owner.scope, extra: owner.scopeExtra, in: project)
        guard !check.isInScope else { return AgentScopeDecision(owner: owner, inScope: true) }
        let outside = check.summary(in: project)
        DebugLog.write("edit", "scope guard (\(mode.rawValue)) stopped an edit by \(author): \(check.items.count) "
            + "item(s) outside, project-wide: \(check.projectWide.joined(separator: ", "))")
        guard mode == .ask else {
            throw RPCFailure(
                -32004, "Blocked: this edit changes \(outside), outside the attached scope. Ask the user to attach "
                    + "these items or to change them themselves.", data: check.json)
        }
        guard scopeHold == nil else {
            throw RPCFailure(-32003, "Another edit outside the scope is waiting for the user; retry after they answer")
        }
        let hold = AgentScopeHold(
            id: UUID(), operation: operation, label: label, author: author, coalescingKey: coalescingKey,
            token: token, agent: owner.title, outside: outside)
        scopeHold = hold
        owner.scopeLast = nil
        NSApp.activate(ignoringOtherApps: true)
        var data = check.json.object
        data["held"] = .bool(true)
        data["request"] = .string(hold.id.uuidString)
        throw RPCFailure(
            -32004, "Held: this edit changes \(outside), outside the attached scope. BashCut is asking the user and "
                + "applies the edit only if they allow it. Do not retry: read context get (scope.held, scope.last) "
                + "for their answer.", data: .object(data))
    }

    /// The user's answer to a held edit: Allow Once or Allow for This Request apply it now (on the current project),
    /// Reject drops it. `context get` reports the outcome to the agent as `scope.last`.
    func resolveScopeHold(_ choice: AgentScopeChoice) {
        guard let hold = scopeHold else { return }
        scopeHold = nil
        let owner = scopeOwner(for: hold.token)
        var outcome: [String: JSONValue] = ["request": .string(hold.id.uuidString), "label": .string(hold.label)]
        switch choice {
        case .reject:
            outcome["outcome"] = .string("rejected")
            message = String(format: String(localized: "Rejected an edit by %@ outside the attached clips"), hold.agent)
        case .allowOnce, .allowRequest:
            if choice == .allowRequest { owner?.scopeAllowed = true }
            do {
                // Run as the user's decision: no session token, so the guard does not stop it again.
                let result = try CommandCaller.$token.withValue(nil) {
                    try commitEdit(
                        hold.operation, label: hold.label, author: hold.author, coalescingKey: hold.coalescingKey)
                }
                outcome["outcome"] = .string("applied")
                outcome["rev"] = .integer(result.revision)
            } catch {
                outcome["outcome"] = .string("failed")
                outcome["error"] = .string(error.localizedDescription)
                message = error.localizedDescription
            }
        }
        DebugLog.write("edit", "held edit by \(hold.author) \(choice.rawValue): \(outcome["outcome"]?.string ?? "")")
        owner?.scopeLast = .object(outcome)
    }

    /// After an in-scope edit, the items it made join the scope, so later edits to them are not asked.
    func recordScopeEdit(_ decision: AgentScopeDecision, before: Project) {
        guard decision.inScope, let owner = decision.owner else { return }
        let old = Set(before.tracks.flatMap(\.items).map(\.id))
        owner.scopeExtra.formUnion(project.tracks.flatMap(\.items).map(\.id).filter { !old.contains($0) })
    }

    /// `context get`'s `agentPermissions`: what agents may do without asking, as the user set it in Settings › Agents.
    var agentPermissionsJSON: JSONValue {
        .object([
            "edits": .bool(settings.agentsCanEdit), "autoApprove": .bool(settings.agentActionsAutoApproved),
            "scopeGuard": .string(agentScopeMode.rawValue), "allowAll": .bool(settings.dangerouslyAllowAgents),
        ])
    }

    /// `context get`'s `scope`: the caller's own tab, else the shown chat or terminal tab; null without one.
    var agentScopeJSON: JSONValue {
        let owner = CommandCaller.token.flatMap(scopeOwner(for:))
            ?? agents.chatPluginID.map { chatAgents.model(for: $0) } ?? agents.current
        guard let owner else { return .null }
        var fields: [String: JSONValue] = [
            "scope": .array(owner.scope.map(\.json)), "mode": .string(agentScopeMode.rawValue),
            "allowedForRequest": .bool(owner.scopeAllowed),
            "held": scopeHold.flatMap { hold in
                scopeOwner(for: hold.token) === owner
                    ? .object(["request": .string(hold.id.uuidString), "label": .string(hold.label),
                               "outside": .string(hold.outside)])
                    : nil
            } ?? .null,
            "last": owner.scopeLast ?? .null,
        ]
        if let chat = owner as? ChatAgentModel { fields["plugin"] = .string(chat.pluginID) }
        if let session = owner as? TerminalSession { fields["terminal"] = .string(session.provider.id.rawValue) }
        return .object(fields)
    }
}
