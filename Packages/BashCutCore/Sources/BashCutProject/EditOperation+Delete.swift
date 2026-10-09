import Foundation

extension Project {
    /// Deletes an item with its linked partner, except that deleting a clip's sound keeps its picture: the sound is
    /// unlinked and deleted alone.
    mutating func deleteLinked(_ id: String, ripple: Bool) throws {
        let (track, index) = try location(id)
        if let video = tracks[track].items[index].fields["linkedVideo"]?.string {
            if let picture = try? location(video) { tracks[picture.0].items[picture.1].fields["linkedAudio"] = nil }
            try deleteItem(id: id, ripple: ripple)
            return
        }
        let linked = try linkedItemID(id)
        try deleteItem(id: id, ripple: ripple)
        if let linked { try deleteItem(id: linked, ripple: ripple) }
    }
}
