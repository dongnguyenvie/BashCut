@preconcurrency import AVFoundation
import BashCutProject
import CoreGraphics

/// Measures an exported file (P1-E6): stream start times, frame rate and size, black stretches (two samples a
/// second, the same black test as the picture review) and silent stretches (10 ms levels at or under the silence
/// floor for at least a quarter second).
public enum DeliveredQC {
    public static func measure(
        _ url: URL, revision: Int, preset: String, expectedFps: Double, expectedSize: (Int, Int)
    ) async throws -> DeliveredFacts {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProjectError.invalid("The export has no picture")
        }
        let (range, average, size) = try await video.load(.timeRange, .nominalFrameRate, .naturalSize)
        // nominalFrameRate averages over the track, so a held frame (an encoder writes a still or black stretch as
        // one long frame) lowers it; the frame times give the rate frames are written at.
        let rate = DeliveredFacts.writtenRate(try frameTimes(asset, track: video)) ?? Double(average)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let audioStart = try await audio?.load(.timeRange).start.seconds
        let black = try await blackRanges(asset, duration: duration)
        let silence = try await silentRanges(asset)
        return DeliveredFacts(
            revision: revision, preset: preset, path: url.path, videoStart: range.start.seconds, audioStart: audioStart,
            fps: rate, expectedFps: expectedFps, size: (Int(size.width), Int(size.height)), expectedSize: expectedSize,
            duration: duration, black: black, silence: silence, averageFps: Double(average))
    }

    /// Presentation times of the picture's samples, read without decoding.
    static func frameTimes(_ asset: AVAsset, track: AVAssetTrack) throws -> [Double] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { return [] }
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if time.isValid, CMSampleBufferGetNumSamples(sample) > 0 { times.append(time.seconds) }
        }
        return times
    }

    static func blackRanges(_ asset: AVAsset, duration: Double) async throws -> [ClosedRange<Double>] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 96, height: 96)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let times = stride(from: 0.0, to: duration, by: 0.5).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var dark: [Double: Bool] = [:]
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            let stats = (try? result.image).flatMap(PictureSampler.thumbnail).map(PictureSampler.statistics)
            dark[result.requestedTime.seconds] = stats.map { $0.mean < ReviewPicture.blackLuma && $0.spread < ReviewPicture.flatSpread } ?? true
        }
        return runs(times.map(\.seconds), step: 0.5) { dark[$0] ?? false }
    }

    static func silentRanges(_ asset: AVAsset) async throws -> [ClosedRange<Double>] {
        guard let levels = try await RenderDrift.envelope(asset, mix: nil) else { return [] }
        let times = levels.indices.map { Double($0) / 100 }
        return runs(times, step: 0.01) { Double(levels[Int(($0 * 100).rounded())]) <= MixMeasure.silenceLUFS }
            .filter { $0.upperBound - $0.lowerBound >= 0.25 }
    }

    /// Consecutive times where `test` holds, as ranges ending one step after the last.
    static func runs(_ times: [Double], step: Double, where test: (Double) -> Bool) -> [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = []
        var start: Double?
        for time in times {
            if test(time) {
                if start == nil { start = time }
            } else if let open = start {
                ranges.append(open...time)
                start = nil
            }
        }
        if let open = start, let last = times.last { ranges.append(open...(last + step)) }
        return ranges
    }
}
