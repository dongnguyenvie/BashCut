@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// Creates the preview proxies `ProxyMediaSource` reads: `.bashcut/cache/proxies/<media id>.mov`, H.264 with a
/// keyframe every 10 frames and no reordering at most 960 px on the long side, with AAC sound. Every frame
/// keeps its original presentation time, so items need no change and export keeps reading the original.
public struct ProxyManager: Sendable {
    /// What makes footage heavy enough to need a proxy.
    public struct Policy: Sendable {
        /// Longer side above this many pixels.
        public var maximumDimension: Double = 1920
        /// Average video bit rate above this.
        public var maximumBitsPerSecond: Float = 20_000_000
        /// Long-GOP codecs that are slow to seek on this class of footage.
        public var heavyCodecs: Set<FourCharCode> = [kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha]

        public init() {}
    }

    public struct Probe: Sendable, Equatable {
        public let codec: String
        public let width: Int
        public let height: Int
        public let bitsPerSecond: Float
        public let needsProxy: Bool
    }

    public static let longSide = 960
    public static let keyframeInterval = 10
    public var policy: Policy

    public init(policy: Policy = Policy()) { self.policy = policy }

    /// Where `media`'s proxy goes, or nil when its ID cannot be a file name.
    public static func destination(for media: Media, root: URL) -> URL? {
        guard ProxyMediaSource.isSafe(media.id) else { return nil }
        return root.appendingPathComponent(ProxyMediaSource.folder, isDirectory: true)
            .appendingPathComponent(media.id).appendingPathExtension("mov")
    }

    /// Codec, size and bit rate of the first video track, and whether the policy wants a proxy.
    /// Nil for files without video.
    public func probe(_ url: URL) async throws -> Probe? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (size, transform, rate, descriptions) = try await track.load(
            .naturalSize, .preferredTransform, .estimatedDataRate, .formatDescriptions)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let codec = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let needsProxy = max(abs(rect.width), abs(rect.height)) > policy.maximumDimension
            || rate > policy.maximumBitsPerSecond || policy.heavyCodecs.contains(codec)
        return Probe(
            codec: Self.fourCC(codec), width: Int(abs(rect.width)), height: Int(abs(rect.height)),
            bitsPerSecond: rate, needsProxy: needsProxy)
    }

    /// Writes the proxy for `source` to `destination` (through a temporary file, so a cancelled or failed
    /// run leaves nothing behind). `progress` receives 0…1.
    public func generate(
        from source: URL, to destination: URL, progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProjectError.invalid("\(source.lastPathComponent) has no video to make a proxy from")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (duration, (size, transform, frameRate, timeScale)) = try await (
            asset.load(.duration), video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .naturalTimeScale))
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial.mov")
        defer { try? FileManager.default.removeItem(at: partial) }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)
        let videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: Self.videoSettings(size: size, frameRate: frameRate))
        videoInput.transform = transform
        // Keep the source's time scale so 29.97 fps frame times are stored exactly, not rounded to 1/600 s.
        videoInput.mediaTimeScale = timeScale
        writer.movieTimeScale = timeScale
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        var lanes = [Lane(output: videoOutput, input: videoInput, reportsProgress: true)]
        if let audio {
            let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(audioOutput)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
            ])
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            lanes.append(Lane(output: audioOutput, input: audioInput, reportsProgress: false))
        }
        guard reader.startReading() else { throw reader.error ?? ProjectError.invalid("Could not read the source") }
        guard writer.startWriting() else { throw writer.error ?? ProjectError.invalid("Could not write the proxy") }
        writer.startSession(atSourceTime: .zero)
        do {
            try await Self.copy(lanes, duration: duration.seconds, progress: progress)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        if reader.status == .failed { writer.cancelWriting(); throw reader.error ?? ProjectError.invalid("Read failed") }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProjectError.invalid("Proxy write failed") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        progress?(1)
    }

    // MARK: - Writing

    private struct Lane: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        let reportsProgress: Bool
    }

    private static func videoSettings(size: CGSize, frameRate: Float) -> [String: Any] {
        let scale = min(1, Double(longSide) / max(size.width, size.height))
        // H.264 wants even dimensions.
        let width = max(2, Int((size.width * scale / 2).rounded()) * 2)
        let height = max(2, Int((size.height * scale / 2).rounded()) * 2)
        return [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: max(1, Int(frameRate.rounded())),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
    }

    /// Pulls every lane until its reader output runs dry. Inputs that are not ready are polled, which keeps
    /// this a plain async loop instead of juggling `requestMediaDataWhenReady` queues.
    private static func copy(
        _ lanes: [Lane], duration: Double, progress: (@Sendable (Double) -> Void)?
    ) async throws {
        var finished = Array(repeating: false, count: lanes.count)
        var lastReported = -1.0
        while finished.contains(false) {
            try Task.checkCancellation()
            var wrote = false
            for index in lanes.indices where !finished[index] && lanes[index].input.isReadyForMoreMediaData {
                let lane = lanes[index]
                guard let buffer = lane.output.copyNextSampleBuffer() else {
                    lane.input.markAsFinished()
                    finished[index] = true
                    continue
                }
                guard lane.input.append(buffer) else { throw ProjectError.invalid("Proxy encoder rejected a frame") }
                wrote = true
                if lane.reportsProgress, duration > 0 {
                    let done = min(0.99, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration)
                    if done - lastReported >= 0.01 { lastReported = done; progress?(done) }
                }
            }
            if !wrote { try await Task.sleep(for: .milliseconds(2)) }
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
    }
}
