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
    }
    private var lanes: [Lane] = []
    private var indices: [String: [Int]] = [:]

    var parameters: [AVAudioMixInputParameters] { lanes.map(\.parameters) }

    mutating func take(for item: Item, sourceTrack: String, gain: [AudioGainPoint], composition: AVMutableComposition) throws
        -> (track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters)
    {
        let preservesPitch = item["preservePitch"] != .bool(false)
        // The native mixer can interpolate across touching ramps with different endpoint gains.
        // Keep a discontinuous cut on another lane; a later cut can reuse either lane after a gap.
        if let index = indices[sourceTrack]?.first(where: {
            lanes[$0].preservesPitch == preservesPitch
                && (lanes[$0].end < item.at || (lanes[$0].end == item.at && lanes[$0].endVolume == gain.first?.volume))
        }) {
            lanes[index].end = item.end
            lanes[index].endVolume = gain.last?.volume ?? 1
            return (lanes[index].track, lanes[index].parameters)
        }
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Could not allocate audio layer")
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTimePitchAlgorithm = preservesPitch ? .spectral : .varispeed
        indices[sourceTrack, default: []].append(lanes.count)
        lanes.append(Lane(preservesPitch: preservesPitch, track: track, parameters: parameters,
                          end: item.end, endVolume: gain.last?.volume ?? 1))
        return (track, parameters)
    }
}
