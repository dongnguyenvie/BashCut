// BashCut Audio Analysis: the core plugin that provides `audio.loudness` and `audio.beats` with AVFoundation and
// vDSP, so loudness-normalized export and beat grids work without installing anything.
//
// Plugin API one-shot transport: `provider rpc` reads one JSON request from stdin and writes one JSON response.
import AVFoundation
import BashCutAudioAnalysis
import Foundation

/// Deinterleaved float channels of the file's first audio track at `sampleRate`, at most `maximumChannels`
/// (more are mixed down by AVFoundation).
func decode(_ path: String, sampleRate: Double, maximumChannels: Int) async throws -> [[Float]] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw AnalysisError("The file has no audio")
    }
    let sourceChannels = try await track.load(.formatDescriptions).first
        .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 1
    let channels = max(1, min(maximumChannels, Int(sourceChannels)))
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
    ])
    reader.add(output)
    guard reader.startReading() else {
        throw AnalysisError("Cannot decode the audio: \(reader.error?.localizedDescription ?? "unknown error")")
    }
    var interleaved: [Float] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        chunk.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        interleaved += chunk
    }
    if reader.status == .failed {
        throw AnalysisError("Cannot decode the audio: \(reader.error?.localizedDescription ?? "unknown error")")
    }
    let frames = interleaved.count / channels
    return (0..<channels).map { channel in (0..<frames).map { interleaved[$0 * channels + channel] } }
}

func mediaPath(_ params: [String: Any]) throws -> String {
    guard let path = params["mediaPath"] as? String, FileManager.default.fileExists(atPath: path) else {
        throw AnalysisError("The media file is missing")
    }
    return path
}

func loudness(_ params: [String: Any]) async throws -> [String: Any] {
    let channels = try await decode(mediaPath(params), sampleRate: LoudnessMeter.sampleRate, maximumChannels: 2)
    let result = try LoudnessMeter.measure(channels)
    var values: [String: Any] = [
        "integratedLUFS": (result.integratedLUFS * 10).rounded() / 10,
        "truePeakDbTP": (result.truePeakDbTP * 10).rounded() / 10,
    ]
    if let range = result.loudnessRangeLU { values["loudnessRangeLU"] = (range * 10).rounded() / 10 }
    return values
}

func beats(_ params: [String: Any]) async throws -> [String: Any] {
    let channels = try await decode(mediaPath(params), sampleRate: BeatTracker.sampleRate, maximumChannels: 1)
    let result = try BeatTracker.track(channels[0])
    return ["bpm": result.bpm, "beatsSeconds": result.beatsSeconds]
}

func handle(_ request: [String: Any]) async -> [String: Any] {
    let id = request["id"] ?? ""
    let params = request["params"] as? [String: Any] ?? [:]
    do {
        switch request["method"] as? String {
        case "audio.loudness": return ["id": id, "result": try await loudness(params)]
        case "audio.beats": return ["id": id, "result": try await beats(params)]
        default: return ["id": id, "error": ["code": "unknown_method", "message": "\(request["method"] ?? "")"]]
        }
    } catch {
        return ["id": id, "error": ["code": "analysis_failed", "message": String(describing: error)]]
    }
}

guard CommandLine.arguments.dropFirst().first == "rpc" else {
    FileHandle.standardError.write(Data("usage: provider rpc\n".utf8))
    exit(2)
}
let line = readLine(strippingNewline: true) ?? ""
let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
let response = try JSONSerialization.data(withJSONObject: await handle(request))
FileHandle.standardOutput.write(response + Data([0x0A]))
