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

    private func performExport(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Export destination already exists")
        }
        let reader = try AVAssetReader(asset: snapshot.composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: settings?.preset.fileType ?? .mp4)
        var completed = false
        defer {
            if !completed {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
        }
        let tracks = try await snapshot.composition.loadTracks(withMediaType: .video)
        let video = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        video.videoComposition = snapshot.videoComposition
        let size = snapshot.videoComposition.renderSize
        var compression: [String: Any] = [:]
        if let bitRate = settings?.preset.videoBitRate {
            compression[AVVideoAverageBitRateKey] = bitRate
        }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: settings?.preset.videoCodec ?? .h264, AVVideoWidthKey: Int(size.width),
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
        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(video, videoInput)]
        let audioTracks = try await snapshot.composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let audio = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            audio.audioMix = snapshot.audioMix
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
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
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? ProjectError.invalid("Export could not start")
        }
        writer.startSession(atSourceTime: .zero)
        progress(0)
        try await transferSamples(
            pairs, duration: snapshot.composition.duration.seconds, reader: reader, writer: writer,
            progress: progress)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? ProjectError.invalid("Export failed")
        }
        completed = true
        progress(1)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return ExportReceipt(
            url: url, duration: snapshot.composition.duration.seconds,
            bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }
    private func transferSamples(
        _ pairs: [(AVAssetReaderOutput, AVAssetWriterInput)],
        duration: Double, reader: AVAssetReader, writer: AVAssetWriter,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var finished = Set<Int>()
        var lastProgress = -1.0
        while finished.count < pairs.count {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw writer.error ?? ProjectError.invalid("Writer stopped")
            }
            for (index, pair) in pairs.enumerated()
            where !finished.contains(index) && pair.1.isReadyForMoreMediaData {
                if let sample = pair.0.copyNextSampleBuffer() {
                    guard pair.1.append(sample) else {
                        throw writer.error ?? ProjectError.invalid("Cannot write sample")
                    }
                    if index == 0, duration > 0 {
                        let value = min(0.99, max(0, sample.presentationTimeStamp.seconds / duration))
                        if value - lastProgress >= 0.005 {
                            lastProgress = value
                            progress(value)
                        }
                    }
                } else {
                    pair.1.markAsFinished()
                    finished.insert(index)
                }
            }
            if reader.status == .failed {
                throw reader.error ?? ProjectError.invalid("Cannot read media")
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

}
