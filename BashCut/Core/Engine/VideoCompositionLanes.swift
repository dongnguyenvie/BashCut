@preconcurrency import AVFoundation
import BashCutProject

/// Allocate both clips and transition holds from the same non-overlapping lanes of each project layer.
struct VideoCompositionLanes {
    private var layers: [String: [(end: Int, track: AVMutableCompositionTrack)]] = [:]

    mutating func take(layer: String, start: Int, end: Int, composition: AVMutableComposition) throws -> AVMutableCompositionTrack {
        var lanes = layers[layer] ?? []
        if let index = lanes.firstIndex(where: { $0.end <= start }) {
            lanes[index].end = end
            layers[layer] = lanes
            return lanes[index].track
        }
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Could not allocate video layer")
        }
        lanes.append((end, track))
        layers[layer] = lanes
        return track
    }
}
