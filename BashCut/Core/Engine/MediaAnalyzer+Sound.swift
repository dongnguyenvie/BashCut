@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// File facts and sound levels for `media.analyze`.
extension MediaAnalyzer {
    /// Seconds per level window.
    static let window = 0.1
    /// The rate sound is decoded at for levels.
    static let levelRate = 48_000.0

    /// Container and track facts: sizes, rates, codecs, colour tags and the presentation-time spread of the video
    /// samples (read without decoding).
    static func tech(_ asset: AVURLAsset, url: URL) async throws -> MediaAnalysis.Tech {
        let seconds = try await asset.load(.duration).seconds
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        var tech = MediaAnalysis.Tech(seconds: seconds.isFinite ? seconds : 0, bytes: bytes)
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let (size, nominal, transform, range, descriptions) = try await track.load(
                .naturalSize, .nominalFrameRate, .preferredTransform, .timeRange, .formatDescriptions)
            let description = descriptions.first
            var video = MediaAnalysis.Video(
                codec: description.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) },
                width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                rotation: Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()),
                nominalFPS: Double(nominal), seconds: range.duration.seconds)
            if let description {
                let tag = { (key: CFString) in CMFormatDescriptionGetExtension(description, extensionKey: key) as? String }
                video.transfer = tag(kCMFormatDescriptionExtension_TransferFunction)
                video.primaries = tag(kCMFormatDescriptionExtension_ColorPrimaries)
                video.matrix = tag(kCMFormatDescriptionExtension_YCbCrMatrix)
                video.bitDepth = (CMFormatDescriptionGetExtension(
                    description, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber)?.intValue
            }
            if let timing = try? frameTiming(asset, track: track) {
                (video.frames, video.minFrameSeconds, video.maxFrameSeconds, video.meanFrameSeconds) = timing
            }
            tech.video = video
        }
        if let track = try await asset.loadTracks(withMediaType: .audio).first {
            let (range, descriptions) = try await track.load(.timeRange, .formatDescriptions)
            let basic = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            tech.audio = MediaAnalysis.SoundTrack(
                codec: descriptions.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) },
                channels: Int(basic?.mChannelsPerFrame ?? 0), sampleRate: basic?.mSampleRate ?? 0,
                seconds: range.duration.seconds)
        }
        return tech
    }

    /// Sample count and shortest, longest and mean presentation-time step of the video samples.
    static func frameTiming(_ asset: AVURLAsset, track: AVAssetTrack) throws -> (Int, Double, Double, Double)? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let time = CMSampleBufferGetOutputPresentationTimeStamp(sample).seconds
            if time.isFinite { times.append(time) }
        }
        times.sort()
        let steps = zip(times, times.dropFirst()).map { $1 - $0 }.filter { $0 > 1e-6 }
        guard let low = steps.min(), let high = steps.max() else { return nil }
        return (times.count, low, high, steps.reduce(0, +) / Double(steps.count))
    }

    /// RMS level per window over all channels, the sample peak, and the correlation of the first two channels.
    static func sound(_ asset: AVURLAsset) async throws -> MediaAnalysis.Sound? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let descriptions = try await track.load(.formatDescriptions)
        let source = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let channels = max(1, min(2, Int(source?.mChannelsPerFrame ?? 1)))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: levelRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var meter = LevelMeter(channels: channels, windowFrames: Int(levelRate * window))
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(buffer)
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw ProjectError.invalid("Cannot read the sound") }
            data.withUnsafeBytes { meter.add($0.bindMemory(to: Float.self)) }
        }
        guard reader.status == .completed else { throw reader.error ?? ProjectError.invalid("Cannot read the sound") }
        return meter.result(window: window)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let characters = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        return String(characters).trimmingCharacters(in: .whitespaces)
    }
}

/// Window RMS, peak and two-channel correlation over interleaved float samples.
struct LevelMeter {
    let channels: Int
    let windowFrames: Int
    private var levels: [Double] = []
    private var power = 0.0
    private var count = 0
    private var peak: Float = 0
    private var (leftRight, leftSquared, rightSquared) = (0.0, 0.0, 0.0)

    init(channels: Int, windowFrames: Int) {
        self.channels = max(1, channels)
        self.windowFrames = max(1, windowFrames)
    }

    mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        for start in stride(from: 0, to: samples.count - channels + 1, by: channels) {
            for channel in 0..<channels {
                let value = samples[start + channel]
                guard value.isFinite else { continue }
                power += Double(value * value)
                peak = max(peak, abs(value))
            }
            if channels > 1 {
                let (left, right) = (Double(samples[start]), Double(samples[start + 1]))
                leftRight += left * right
                leftSquared += left * left
                rightSquared += right * right
            }
            count += 1
            if count == windowFrames { close() }
        }
    }

    private mutating func close() {
        let mean = power / Double(count * channels)
        levels.append(mean > 0 ? max(MediaAnalysis.silenceDb, 10 * log10(mean)) : MediaAnalysis.silenceDb)
        (power, count) = (0, 0)
    }

    mutating func result(window: Double) -> MediaAnalysis.Sound {
        if count > 0 { close() }
        let correlation = channels > 1 && leftSquared > 0 && rightSquared > 0
            ? leftRight / (leftSquared * rightSquared).squareRoot() : nil
        return MediaAnalysis.Sound(
            window: window, levels: levels,
            peakDb: peak > 0 ? max(MediaAnalysis.silenceDb, 20 * log10(Double(peak))) : MediaAnalysis.silenceDb,
            stereoCorrelation: correlation)
    }
}
