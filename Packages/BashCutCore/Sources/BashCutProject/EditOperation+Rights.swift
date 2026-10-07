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
}
