import Foundation

public struct ProjectItemChange: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case added, removed, modified }

    public let kind: Kind
    public let itemID: String
    public let beforeTrackID: String?
    public let beforeTrackName: String?
    public let before: Item?
    public let afterTrackID: String?
    public let afterTrackName: String?
    public let after: Item?

    public var id: String { itemID }
    public var changedKeys: [String] {
        let lhs = before?.fields ?? [:]
        let rhs = after?.fields ?? [:]
        return Set(lhs.keys).union(rhs.keys).filter { lhs[$0] != rhs[$0] }.sorted()
    }
}

public struct ProjectChangeSet: Sendable, Equatable {
    public let projectKeys: [String]
    public let mediaIDs: [String]
    public let trackIDs: [String]
    public let items: [ProjectItemChange]

    public var isEmpty: Bool {
        projectKeys.isEmpty && mediaIDs.isEmpty && trackIDs.isEmpty && items.isEmpty
    }
}

extension Project {
    public func changes(from before: Project) -> ProjectChangeSet {
        let ignoredProjectKeys: Set<String> = ["media", "tracks", "rev"]
        let projectKeys = Set(storage.keys).union(before.storage.keys).filter {
            !ignoredProjectKeys.contains($0) && storage[$0] != before.storage[$0]
        }.sorted()
        let oldMedia = Dictionary(uniqueKeysWithValues: before.media.map { ($0.id, $0.fields) })
        let newMedia = Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0.fields) })
        let mediaIDs = Set(oldMedia.keys).union(newMedia.keys).filter {
            oldMedia[$0] != newMedia[$0]
        }.sorted()
        func trackProperties(_ project: Project) -> [String: [String: JSONValue]] {
            Dictionary(uniqueKeysWithValues: project.tracks.map { track in
                (track.id, track.storage)
            })
        }
        let oldTracks = trackProperties(before)
        let newTracks = trackProperties(self)
        let trackIDs = Set(oldTracks.keys).union(newTracks.keys).filter {
            oldTracks[$0] != newTracks[$0]
        }.sorted()
        return ProjectChangeSet(
            projectKeys: projectKeys, mediaIDs: mediaIDs, trackIDs: trackIDs,
            items: itemChanges(from: before))
    }

    public func itemChanges(from before: Project) -> [ProjectItemChange] {
        typealias Located = (trackID: String, trackName: String, item: Item)
        func index(_ project: Project) -> [String: Located] {
            var result: [String: Located] = [:]
            for track in project.tracks {
                for item in track.items {
                    result[item.id] = (track.id, track.name, item)
                }
            }
            return result
        }
        let old = index(before)
        let new = index(self)
        return Set(old.keys).union(new.keys).compactMap { id in
            let lhs = old[id]
            let rhs = new[id]
            let kind: ProjectItemChange.Kind
            if lhs == nil { kind = .added } else if rhs == nil { kind = .removed } else { kind = .modified }
            guard lhs?.item != rhs?.item || lhs?.trackID != rhs?.trackID else { return nil }
            return ProjectItemChange(
                kind: kind, itemID: id, beforeTrackID: lhs?.trackID,
                beforeTrackName: lhs?.trackName, before: lhs?.item,
                afterTrackID: rhs?.trackID, afterTrackName: rhs?.trackName, after: rhs?.item)
        }.sorted {
            let left = $0.after?.at ?? $0.before?.at ?? 0
            let right = $1.after?.at ?? $1.before?.at ?? 0
            return (left, $0.itemID) < (right, $1.itemID)
        }
    }
}
