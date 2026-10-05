import Foundation

/// A preference change an agent asked for that waits for the user's review (#69): set `key` to `value`, or remove it
/// when `value` is nil. Agents' lessons wait as lessons with status `proposed`; values wait here, in the
/// `proposals.json` of the scope they would change.
public struct KnowledgeValueProposal: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: KnowledgeValueKind
    public var key: String
    public var value: String?
    public var source: KnowledgeSource
    /// The file it was read from, and the scope the value is written to; not stored.
    public var scope: KnowledgeScope = .user

    enum CodingKeys: String, CodingKey { case id, kind, key, value, source }

    public init(
        id: String, kind: KnowledgeValueKind, key: String, value: String?, source: KnowledgeSource,
        scope: KnowledgeScope
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.value = value
        self.source = source
        self.scope = scope
    }
}

extension AgentKnowledgeStore {
    private struct ProposalFile: Codable {
        var version: Int? = 1
        var values: [KnowledgeValueProposal]
    }

    /// Value proposals of one scope, or of both (project first), oldest first.
    public func valueProposals(_ scope: KnowledgeScope? = nil) throws -> [KnowledgeValueProposal] {
        let scopes: [KnowledgeScope] = scope.map { [$0] } ?? (project == nil ? [.user] : [.project, .user])
        return try scopes.flatMap { scope in
            try readProposals(scope).map { proposal in
                var proposal = proposal
                proposal.scope = scope
                return proposal
            }
        }
    }

    public func valueProposal(_ id: String) throws -> KnowledgeValueProposal {
        guard let proposal = try valueProposals().first(where: { $0.id == id }) else {
            throw KnowledgeError("No proposal \(id)")
        }
        return proposal
    }

    /// Queues a change to a value for review. A newer proposal for the same key replaces the older one.
    @discardableResult
    public func proposeValue(
        _ kind: KnowledgeValueKind, key: String, value: String?, scope: KnowledgeScope, source: KnowledgeSource
    ) throws -> KnowledgeValueProposal {
        guard kind == .prefs || scope == .project else { throw KnowledgeError("Facts belong to one project") }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KnowledgeError("A key cannot be empty") }
        if value == nil, !(try values(kind, scope: scope)).contains(where: { $0.key == key }) {
            throw KnowledgeError("No \(kind.rawValue) key \(key)")
        }
        var all = try readProposals(scope, writable: true)
        all.removeAll { $0.kind == kind && $0.key == key }
        let taken = Set(try valueProposals().map(\.id))
        var id: String
        repeat {
            id = "p-" + UUID().uuidString.prefix(8).lowercased()
        } while taken.contains(id)
        let proposal = KnowledgeValueProposal(id: id, kind: kind, key: key, value: value, source: source, scope: scope)
        all.append(proposal)
        try writeProposals(all, scope: scope)
        return proposal
    }

    /// Applies a proposal, with `value` when the user edited it first. The stored value keeps the agent as its
    /// source; history records the approval by `source`.
    @discardableResult
    public func approveValue(
        _ id: String, value edited: String? = nil, source: KnowledgeSource
    ) throws -> KnowledgeValue? {
        let proposal = try takeProposal(id)
        var author = proposal.source
        author.date = source.date
        return try setValue(
            proposal.kind, key: proposal.key, value: proposal.value == nil ? nil : edited ?? proposal.value,
            scope: proposal.scope, source: author, recordedBy: source, action: .approve)
    }

    /// Drops a proposal; history keeps what was proposed.
    @discardableResult
    public func rejectValue(_ id: String, source: KnowledgeSource) throws -> KnowledgeValueProposal {
        let proposal = try takeProposal(id)
        try record(KnowledgeChange(
            action: .reject, kind: proposal.kind == .prefs ? .prefs : .facts, target: proposal.key, source: source,
            before: .value(KnowledgeValue(
                key: proposal.key, value: proposal.value ?? "", source: proposal.source, scope: proposal.scope)),
            after: nil), scope: proposal.scope)
        return proposal
    }

    private func takeProposal(_ id: String) throws -> KnowledgeValueProposal {
        let proposal = try valueProposal(id)
        var all = try readProposals(proposal.scope, writable: true)
        all.removeAll { $0.id == id }
        try writeProposals(all, scope: proposal.scope)
        return proposal
    }

    private func readProposals(_ scope: KnowledgeScope, writable: Bool = false) throws -> [KnowledgeValueProposal] {
        let file: ProposalFile? = try read("proposals.json", scope: scope, writable: writable)
        return file?.values ?? []
    }

    private func writeProposals(_ proposals: [KnowledgeValueProposal], scope: KnowledgeScope) throws {
        try Self.encoder.encode(ProposalFile(values: proposals))
            .write(to: try folder(scope).appendingPathComponent("proposals.json"), options: .atomic)
    }
}
