@preconcurrency import AVFoundation
import BashCutProject

/// Allocate both clips and transition holds from the same non-overlapping lanes of each project layer. Only clips
/// whose pictures decode alike (`decoderKey`) share a lane: an 8-bit H.264 clip after a 10-bit HLG HEVC clip on one
/// composition track got no source frame in the compositor, and the export failed at the join.
struct VideoCompositionLanes {
    private var layers: [String: [(end: Int, decoder: String, track: AVMutableCompositionTrack)]] = [:]

    mutating func take(
        layer: String, start: Int, end: Int, decoder: String, composition: AVMutableComposition
    ) throws -> AVMutableCompositionTrack {
        var lanes = layers[layer] ?? []
        if let index = lanes.firstIndex(where: { $0.end <= start && $0.decoder == decoder }) {
            lanes[index].end = end
            layers[layer] = lanes
            return lanes[index].track
        }
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Could not allocate video layer")
        }
        lanes.append((end, decoder, track))
        layers[layer] = lanes
        return track
    }

    /// What decides how a video track's pictures decode: the codec, the bits per component and the transfer
    /// function of its first format description ("hvc1 10 ITU_R_2100_HLG", "avc1").
    static func decoderKey(_ description: CMFormatDescription?) -> String {
        guard let description else { return "" }
        var parts = [VideoDecoders.fourCC(CMFormatDescriptionGetMediaSubType(description))]
        if let bits = CMFormatDescriptionGetExtension(description, extensionKey: "BitsPerComponent" as CFString) as? Int {
            parts.append(String(bits))
        }
        if let transfer = CMFormatDescriptionGetExtension(
            description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
            parts.append(transfer)
        }
        return parts.joined(separator: " ")
    }
}
