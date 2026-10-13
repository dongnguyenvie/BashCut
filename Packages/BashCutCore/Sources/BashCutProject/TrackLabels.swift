import Foundation

// Short layer labels like other editors use (#531): V1, V2… for visual layers from the back (bottom of the timeline)
// to the front, A1, A2… for audio layers from the top of the audio stack down. They come from the layer order and are
// display only: nothing stores them, and a layer's label changes when layers move.

extension Project {
    /// Each layer's short label by track ID.
    public var trackLabels: [String: String] {
        var labels: [String: String] = [:]
        var visual = 0
        var audio = 0
        for track in tracks {
            if track.isVisual {
                visual += 1
                labels[track.id] = "V\(visual)"
            } else {
                audio += 1
                labels[track.id] = "A\(audio)"
            }
        }
        return labels
    }

    /// The short label of one layer, or nil when there is no such layer.
    public func trackLabel(_ trackID: String) -> String? { trackLabels[trackID] }

    /// A layer's label and name as the UI shows them together, e.g. `V3 · Captions`; just the name for an unknown ID.
    public func trackTitle(_ track: Track) -> String {
        trackLabel(track.id).map { "\($0) · \(track.name)" } ?? track.name
    }

    /// The track ID a command's `track` argument names: a track ID as is, otherwise a label such as `V2` or `a1`
    /// (case does not matter). A value that is neither comes back unchanged so the command reports it.
    public func resolveTrackReference(_ reference: String) -> String {
        guard !tracks.contains(where: { $0.id == reference }) else { return reference }
        let wanted = reference.uppercased()
        return trackLabels.first { $0.value == wanted }?.key ?? reference
    }
}
