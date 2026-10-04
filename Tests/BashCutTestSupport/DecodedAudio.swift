import AVFoundation
import Foundation

public extension TestFixtures {
    /// Decode generated test output to 48 kHz stereo float PCM, including compressed AAC movie tracks.
    static func decodeStereo(_ url: URL) async throws -> [[Float]] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw Missing(description: "Generated fixture has no audio")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Missing(description: "Cannot decode fixture") }
        var channels: [[Float]] = [[], []]
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var samples = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: raw.baseAddress!)
            }
            guard status == noErr else { throw Missing(description: "Cannot copy generated PCM") }
            for index in stride(from: 0, to: samples.count - 1, by: 2) {
                channels[0].append(samples[index]); channels[1].append(samples[index + 1])
            }
        }
        guard reader.status == .completed else { throw reader.error ?? Missing(description: "Incomplete fixture audio") }
        return channels
    }
}
