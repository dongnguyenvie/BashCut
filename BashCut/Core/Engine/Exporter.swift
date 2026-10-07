@preconcurrency import AVFoundation
import BashCutProject

public actor Exporter {
    public init() {}

    public func export(_ snapshot: CompositionSnapshot, to url: URL) async throws -> ExportReceipt {
        try await performExport(snapshot, to: url, settings: nil, progress: { _ in })
    }

    public func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ExportReceipt {
        try await performExport(snapshot, to: url, settings: settings, progress: progress)
    }

    /// Lossless 48 kHz stereo PCM for loudness measurement; no video reader or compositor is created.
    public func exportAudio(
        _ snapshot: CompositionSnapshot, to url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ExportReceipt {
        try await performExport(snapshot, to: url, settings: nil, audioOnly: true, progress: progress)
    }

    private func performExport(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings?, audioOnly: Bool = false,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        try Task.checkCancellation()
        let destination = try ExportDestination(url)
        defer { destination.discard() }
        let reader = try AVAssetReader(asset: snapshot.composition)
        let writer = try AVAssetWriter(outputURL: destination.partial, fileType: audioOnly ? .caf : settings?.preset.fileType ?? .mp4)
        writer.shouldOptimizeForNetworkUse = !audioOnly && (settings?.preset.fileType ?? .mp4) == .mp4
        var completed = false
        defer {
            if !completed {
                reader.cancelReading()
                writer.cancelWriting()
            }
        }
        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        if !audioOnly { pairs.append(try await videoPair(snapshot, reader: reader, writer: writer, settings: settings)) }
        let audioTracks = try await snapshot.composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let audio = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks, audioSettings: Self.measurementPCM)
            audio.alwaysCopiesSampleData = false
            audio.audioMix = snapshot.audioMix
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioOnly ? Self.measurementPCM : [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 320000,
                ])
            guard reader.canAdd(audio), writer.canAdd(input) else {
                throw ProjectError.invalid("Cannot configure audio export")
            }
            reader.add(audio)
            writer.add(input)
            pairs.append((audio, input))
        }
        guard !pairs.isEmpty else { throw ProjectError.invalid("Timeline has no audio to measure") }
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? ProjectError.invalid("Export could not start")
        }
        writer.startSession(atSourceTime: .zero)
        progress(0)
        try await transferSamples(
            pairs, snapshot: snapshot, reader: reader, writer: writer,
            progress: progress)
        writer.endSession(atSourceTime: snapshot.composition.duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? ProjectError.invalid("Export failed")
        }
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.partial.path)
        try destination.publish()
        completed = true
        progress(1)
        return ExportReceipt(
            url: url, duration: snapshot.composition.duration.seconds,
            bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }
    private static let measurementPCM: [String: any Sendable] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]

    private func videoPair(
        _ snapshot: CompositionSnapshot, reader: AVAssetReader, writer: AVAssetWriter, settings: ExportSettings?
    ) async throws -> (AVAssetReaderOutput, AVAssetWriterInput) {
        let tracks = try await snapshot.composition.loadTracks(withMediaType: .video)
        let video = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        video.alwaysCopiesSampleData = false
        video.videoComposition = snapshot.videoComposition
        let size = snapshot.videoComposition.renderSize
        let codec = settings?.preset.videoCodec ?? .h264
        var compression: [String: Any] = [:]
        if codec == .h264 {
            let fps = 1 / snapshot.videoComposition.frameDuration.seconds
            guard fps.isFinite, fps > 0 else { throw ProjectError.invalid("Invalid export frame duration") }
            compression[AVVideoExpectedSourceFrameRateKey] = fps
            compression[AVVideoMaxKeyFrameIntervalDurationKey] = 2.0
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        if let bitRate = settings?.effectiveVideoBitRate {
            compression[AVVideoAverageBitRateKey] = bitRate
        }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec, AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        if !compression.isEmpty { videoSettings[AVVideoCompressionPropertiesKey] = compression }
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings)
        guard reader.canAdd(video), writer.canAdd(videoInput) else {
            throw ProjectError.invalid("Cannot configure video export")
        }
        reader.add(video)
        writer.add(videoInput)
        return (video, videoInput)
    }

    private func transferSamples(
        _ pairs: [(AVAssetReaderOutput, AVAssetWriterInput)],
        snapshot: CompositionSnapshot, reader: AVAssetReader, writer: AVAssetWriter,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let end = snapshot.composition.duration
        let lanes = pairs.map { output, input in
            let tail = output is AVAssetReaderVideoCompositionOutput
                ? VideoTail(end: end, frame: snapshot.videoComposition.frameDuration) : nil
            return ExportSampleTransfer.Lane(request: { queue, callback in
                input.requestMediaDataWhenReady(on: queue, using: callback)
            }, ready: { input.isReadyForMoreMediaData }, next: {
                guard let sample = output.copyNextSampleBuffer() ?? tail?.closing() else { return nil }
                tail?.last = sample
                guard input.append(sample) else {
                    throw writer.error ?? ProjectError.invalid("Cannot write sample")
                }
                return sample.presentationTimeStamp.seconds
            }, finish: {
                if writer.status == .writing { input.markAsFinished() }
            })
        }
        let transfer = ExportSampleTransfer(lanes: lanes, duration: end.seconds, progress: progress, failure: {
            if reader.status == .failed { return reader.error ?? ProjectError.invalid("Cannot read media") }
            if reader.status == .cancelled { return CancellationError() }
            if writer.status != .writing { return writer.error ?? ProjectError.invalid("Writer stopped") }
            return nil
        }, interrupt: { reader.cancelReading() })
        try await transfer.run()
    }
}

/// The composition output sends a held picture (freeze frame, still, the last source picture) as one sample. When the
/// timeline ends on one, the video track would end with it; `closing` repeats it on the timeline's last frame.
private final class VideoTail: @unchecked Sendable {
    let end: CMTime
    let frame: CMTime
    var last: CMSampleBuffer?
    private var closed = false

    init(end: CMTime, frame: CMTime) {
        self.end = end
        self.frame = frame
    }

    func closing() -> CMSampleBuffer? {
        guard !closed, let last else { return nil }
        closed = true
        let time = end - frame
        guard time > last.presentationTimeStamp else { return nil }
        var timing = CMSampleTimingInfo(duration: frame, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: last, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleBufferOut: &copy)
        return copy
    }
}
