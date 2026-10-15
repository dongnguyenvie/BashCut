import Foundation

/// A brief kept for reuse: a recent one sent from the New brief sheet, or one the user saved as a template.
public struct BriefRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var prompt: String
    /// The template it started from, if any.
    public var templateID: String?
    public var date: Date
    /// Paths of the footage sent with it (`BriefFootage`), so sending it again brings them back.
    public var footage: [String]?

    public init(
        id: UUID = UUID(), title: String, prompt: String, templateID: String? = nil, date: Date = Date(),
        footage: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.templateID = templateID
        self.date = date
        self.footage = footage
    }
}

/// Recent briefs live with the project (`.bashcut/briefs.json`, like the chat transcripts); saved briefs are the
/// user's own templates, for every project on this Mac (`UserDefaults`).
public enum BriefHistory {
    public static let recentLimit = 5
    public static let savedKey = "briefs.saved"

    /// `record` first, without an older brief with the same request, at most `limit` long.
    public static func adding(_ record: BriefRecord, to list: [BriefRecord], limit: Int = recentLimit) -> [BriefRecord] {
        let request = record.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = list.filter { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) != request }
        return Array(([record] + rest).prefix(limit))
    }

    public static func recentFile(project folder: URL) -> URL {
        folder.appendingPathComponent(".bashcut/briefs.json")
    }

    private struct File: Codable { var recent: [BriefRecord] }

    /// The project's recent briefs; empty when there are none or the file cannot be read.
    public static func loadRecent(project folder: URL) -> [BriefRecord] {
        guard let data = try? Data(contentsOf: recentFile(project: folder)) else { return [] }
        return (try? JSONDecoder.briefs.decode(File.self, from: data).recent) ?? []
    }

    public static func saveRecent(_ list: [BriefRecord], project folder: URL) throws {
        let url = recentFile(project: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.briefs.encode(File(recent: list)).write(to: url, options: .atomic)
    }

    public static func loadSaved(_ defaults: UserDefaults = .standard) -> [BriefRecord] {
        guard let data = defaults.data(forKey: savedKey) else { return [] }
        return (try? JSONDecoder.briefs.decode([BriefRecord].self, from: data)) ?? []
    }

    public static func storeSaved(_ list: [BriefRecord], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder.briefs.encode(list) { defaults.set(data, forKey: savedKey) }
    }
}

private extension JSONEncoder {
    static var briefs: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var briefs: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
