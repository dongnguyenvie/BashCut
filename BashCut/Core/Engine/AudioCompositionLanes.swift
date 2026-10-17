@preconcurrency import AVFoundation
import BashCutProject

/// Reuse non-overlapping segments while keeping independent project layers and pitch algorithms separate.
struct AudioCompositionLanes {
    private struct Lane {
        let preservesPitch: Bool
        let track: AVMutableCompositionTrack
        let parameters: AVMutableAudioMixInputParameters
        var end: Int
        var endVolume: Float
        /// The last segment is sound the composition time-scales (a constant speed it plays itself).
        var endScaled: Bool
    }
    private var lanes: [Lane] = []
    private var indices: [String: [Int]] = [:]

    var parameters: [AVAudioMixInputParameters] { lanes.map(\.parameters) }

    /// `scaled`: the item's sound is time-scaled by the composition (`scaleTimeRange`), not played at 1× or from an
    /// offline render.
    mutating func take(
        for item: Item, sourceTrack: String, gain: [AudioGainPoint], scaled: Bool = false,
        composition: AVMutableComposition
    ) throws -> (track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters) {
        let preservesPitch = item["preservePitch"] != .bool(false)
        // The native mixer can interpolate across touching ramps with different endpoint gains.
        // Keep a discontinuous cut on another lane; a later cut can reuse either lane after a gap.
        // A time-scaled segment never touches another segment on its lane: AVFoundation's audio mix output can stop
        // answering inside such a join (a 1.5× clip right after another cut froze an export at 17.3 s). Clips at the
        // same gain (all at -96 dB) used to share one lane and froze; at different gains they were already apart.
        if let index = indices[sourceTrack]?.first(where: {
            lanes[$0].preservesPitch == preservesPitch
                && (lanes[$0].end < item.at
                    || (lanes[$0].end == item.at && !scaled && !lanes[$0].endScaled
                        && lanes[$0].endVolume == gain.first?.volume))
        }) {
            lanes[index].end = item.end
            lanes[index].endVolume = gain.last?.volume ?? 1
            lanes[index].endScaled = scaled
            return (lanes[index].track, lanes[index].parameters)
        }
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Could not allocate audio layer")
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTimePitchAlgorithm = preservesPitch ? .spectral : .varispeed
        indices[sourceTrack, default: []].append(lanes.count)
        lanes.append(Lane(preservesPitch: preservesPitch, track: track, parameters: parameters,
                          end: item.end, endVolume: gain.last?.volume ?? 1, endScaled: scaled))
        return (track, parameters)
    }
}
