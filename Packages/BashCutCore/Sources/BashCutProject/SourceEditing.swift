import Foundation

public enum PlacementMode: String, Sendable { case insert, overwrite }

extension Project {
    /// In and exclusive Out are source frames; destination is a timeline frame.
    /// Planning returns ordinary operations so one application is one revision and undo step.
    public func sourceEdit(
        mediaID: String, sourceRange: Range<Int>, at: Int,
        trackID: String, mode: PlacementMode, itemID: String = UUID().uuidString
    ) throws -> EditOperation {
        let sourceIn = sourceRange.lowerBound
        let sourceOut = sourceRange.upperBound
        try validate()
        guard let asset = media.first(where: { $0.id == mediaID }),
            let track = tracks.first(where: { $0.id == trackID }), track.kind != "text",
            sourceIn >= 0, sourceOut > sourceIn, sourceOut <= asset.frames, at >= 0
        else {
            throw ProjectError.invalid("Invalid source range or destination track")
        }
        let converted = (Double(sourceOut - sourceIn) / asset.fps.value * fps.value).rounded(.down)
        guard converted >= 1, converted <= 2_000_000_000, at <= 2_000_000_000 - Int(converted) else {
            throw ProjectError.invalid("Source range is too short or too long for this timeline")
        }
        var item = Item(
            id: itemID, media: mediaID, at: at, duration: Int(converted), sourceIn: sourceIn)
        var operations = try placementOperations(for: item, on: track, mode: mode)
        if track.kind == "video", asset.hasAudio == true,
            let dialogue = tracks.first(where: { $0.kind == "audio" && $0.role == "dialogue" })
        {
            let audioID = itemID + "-audio"
            item.fields["linkedAudio"] = .string(audioID)
            var audio = Item(
                id: audioID, media: mediaID, at: at, duration: Int(converted), sourceIn: sourceIn)
            audio.fields["linkedVideo"] = .string(itemID)
            operations.append(.insert(track: dialogue.id, item: audio))
        }
        operations.append(.insert(track: trackID, item: item))
        return .group(
            label: mode == .insert ? "Insert source range" : "Overwrite source range", author: .user,
            ops: operations)
    }
    private func placementOperations(for item: Item, on track: Track, mode: PlacementMode) throws
        -> [EditOperation]
    {
        var operations: [EditOperation] = []
        for existing in track.items {
            switch mode {
            case .insert:
                if existing.at >= item.at {
                    guard existing.at <= 2_000_000_000 - item.duration else {
                        throw ProjectError.invalid("Timeline frame overflow")
                    }
                    operations.append(
                        .move(item: existing.id, toTrack: track.id, atFrame: existing.at + item.duration))
                } else if existing.end > item.at {
                    let rightID = UUID().uuidString
                    operations.append(.split(item: existing.id, atFrame: item.at, newID: rightID))
                    operations.append(.move(item: rightID, toTrack: track.id, atFrame: item.end))
                }
            case .overwrite:
                guard existing.at < item.end && existing.end > item.at else { continue }
                if existing.at < item.at {
                    if existing.end > item.end {
                        operations.append(
                            .split(item: existing.id, atFrame: item.end, newID: UUID().uuidString))
                    }
                    operations.append(.trim(item: existing.id, edge: .end, toFrame: item.at, ripple: false))
                } else if existing.end > item.end {
                    operations.append(
                        .trim(item: existing.id, edge: .start, toFrame: item.end, ripple: false))
                } else {
                    operations.append(.delete(item: existing.id, ripple: false))
                }
            }
        }
        return operations
    }

}
