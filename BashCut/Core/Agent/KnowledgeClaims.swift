import BashCutProject
import Foundation

/// One claim the video makes and where it comes from (P3-I5): a number, price, superlative or name as the text or
/// voiceover states it, with a source (a URL, a frame such as `C0042@12.5`, or `user` when the user said so). Review
/// lists claims in titles and the voiceover that no entry covers.
public struct KnowledgeClaim: Codable, Hashable, Sendable {
    public var key: String
    /// The claim as the video states it ("528 ha", "rẻ nhất", "Phở Thìn").
    public var text: String
    /// Where it comes from: a URL, a frame (`MEDIA@SECONDS`), a file, or `user`.
    public var source: String
    public var author: KnowledgeSource

    public init(key: String, text: String, source: String, author: KnowledgeSource) {
        self.key = key
        self.text = text
        self.source = source
        self.author = author
    }
}

extension AgentKnowledgeStore {
    private struct ClaimFile: Codable {
        var version: Int? = 1
        var claims: [KnowledgeClaim]
    }

    /// The project's claims ledger (`.bashcut/knowledge/claims.json`); empty without a saved project.
    public func claims() throws -> [KnowledgeClaim] {
        let file: ClaimFile? = try read("claims.json", scope: .project, writable: false)
        return file?.claims ?? []
    }

    /// Sets a claim (text and source), or removes it when `text` is nil.
    @discardableResult
    public func setClaim(key: String, text: String?, source: String?, author: KnowledgeSource) throws -> KnowledgeClaim? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KnowledgeError("A key cannot be empty") }
        let file: ClaimFile? = try read("claims.json", scope: .project, writable: true)
        var all = file?.claims ?? []
        let index = all.firstIndex { $0.key == key }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            guard let index else { throw KnowledgeError("No claim \(key)") }
            all.remove(at: index)
            try writeClaims(all)
            return nil
        }
        let source = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, !source.isEmpty else { throw KnowledgeError("A claim needs its text and a source") }
        let claim = KnowledgeClaim(key: key, text: text, source: source, author: author)
        if let index { all[index] = claim } else { all.append(claim) }
        try writeClaims(all)
        return claim
    }

    private func writeClaims(_ claims: [KnowledgeClaim]) throws {
        try Self.encoder.encode(ClaimFile(claims: claims))
            .write(to: try folder(.project).appendingPathComponent("claims.json"), options: .atomic)
    }
}
