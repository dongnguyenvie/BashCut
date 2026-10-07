import Foundation

extension Project {
    /// `setMediaRights` (P2-H8): nil leaves a field as it is, JSON null removes it; validation runs with the project.
    mutating func setMediaRights(media id: String, license: JSONValue?, provenance: JSONValue?) throws {
        guard let index = media.firstIndex(where: { $0.id == id }) else { throw ProjectError.invalid("Unknown media \(id)") }
        for (key, value) in [("license", license), ("provenance", provenance)] {
            guard let value else { continue }
            media[index].fields[key] = value == .null ? nil : value
        }
    }

    /// `setMediaData` (P2-H10): free fields the agent keeps on a media; an empty `data` is removed.
    mutating func setMediaData(media id: String, patch: [String: JSONValue]) throws {
        guard let index = media.firstIndex(where: { $0.id == id }) else { throw ProjectError.invalid("Unknown media \(id)") }
        guard !patch.isEmpty, patch.keys.allSatisfy({ (1...64).contains($0.count) }) else {
            throw ProjectError.invalid("media.\(id).data: patch needs keys of 1–64 characters")
        }
        var data = media[index].fields["data"]?.object ?? [:]
        for (key, value) in patch { data[key] = value == .null ? nil : value }
        media[index].fields["data"] = data.isEmpty ? nil : .object(data)
    }
}
