@preconcurrency import AVFoundation
import BashCutProject

/// Reuse non-overlapping segments while keeping independent project layers and pitch algorithms separate.
struct AudioCompositionLanes {
    private struct Lane {
        let preservesPitch: Bool
        let track: AVMutableCompositionTrack
        let parameters: AVMutableAudioMixInputParameters
        var end: Int
    }
    private var lanes: [Lane] = []
    private var indices: [String: [Int]] = [:]

    var parameters: [AVAudioMixInputParameters] { lanes.map(\.parameters) }

    mutating func take(for item: Item, sourceTrack: String, composition: AVMutableComposition) throws
        -> (track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters)
    {
        let preservesPitch = item["preservePitch"] != .bool(false)
        if let index = indices[sourceTrack]?.first(where: {
            lanes[$0].preservesPitch == preservesPitch && lanes[$0].end <= item.at
        }) {
            lanes[index].end = item.end
            return (lanes[index].track, lanes[index].parameters)
        }
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Could not allocate audio layer")
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTimePitchAlgorithm = preservesPitch ? .spectral : .varispeed
        indices[sourceTrack, default: []].append(lanes.count)
        lanes.append(Lane(preservesPitch: preservesPitch, track: track, parameters: parameters, end: item.end))
        return (track, parameters)
    }
}
