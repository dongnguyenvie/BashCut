import Foundation

/// Clip gain (`clip volume`, Inspector › Volume): `volumeDb` on a clip and its linked partner.
extension Project {
    /// The clip gain in dB an item's `volumeDb` accepts.
    public static let volumeDbRange: ClosedRange<Double> = -120...24

    /// `setProperties` of `volumeDb` for several items at once, to apply as one group: each clip with sound and its
    /// linked partner (picture and sound keep the same gain). A partner of a clip already listed is not repeated;
    /// unknown items and items without sound (text, images, graphics) are left out and returned as `skipped`.
    public func volumeOperations(_ ids: [String], db: Double) throws -> (operations: [EditOperation], skipped: [String]) {
        guard db.isFinite, Self.volumeDbRange.contains(db) else {
            throw ProjectError.invalid("Volume must be between \(Self.volumeDbRange.lowerBound) and \(Self.volumeDbRange.upperBound) dB")
        }
        var operations: [EditOperation] = [], skipped: [String] = [], covered = Set<String>()
        let placed = tracks.flatMap { track in track.items.map { (item: $0, track: track) } }
        let items = Dictionary(placed.map { ($0.item.id, $0) }) { first, _ in first }
        for id in ids where !covered.contains(id) {
            guard let found = items[id], SelectionEdits.applies(key: "volumeDb", to: found.item, on: found.track) else {
                skipped.append(id)
                continue
            }
            for target in [id] + (found.item.linkedItemID.map { [$0] } ?? []) where !covered.contains(target) && items[target] != nil {
                covered.insert(target)
                operations.append(.setProperties(item: target, patch: ["volumeDb": .number(db)]))
            }
        }
        return (operations, skipped)
    }
}
