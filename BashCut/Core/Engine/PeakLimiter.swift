@preconcurrency import AVFoundation

/// A look-ahead peak limiter for interleaved float PCM, used by a normalized export so the mix can reach its loudness
/// target without passing the true-peak ceiling (one gain capped by the ceiling stopped 1–2 LU short).
///
/// The output is the input delayed by `lookahead` frames, times a gain that never lets a sample pass `ceiling`: the
/// gain each frame needs is min-filtered over the look-ahead window, then averaged over the same length (so the gain
/// is already down when the peak arrives, without a step), then released slowly. Stereo channels share one gain.
/// The delay (about 1.5 ms) is far below what anyone hears as out of sync.
struct PeakLimiter {
    let ceiling: Float
    let channels: Int
    let lookahead: Int
    private let release: Float
    private var delay: [Float]
    private var delayIndex = 0
    /// Needed gains of the window, with their frame numbers, kept increasing (a monotonic queue for the running min).
    private var minimumQueue: [(frame: Int, gain: Float)] = []
    private var queueStart = 0
    private var averageRing: [Float]
    private var averageSum: Float
    private var averageIndex = 0
    private var gain: Float = 1
    private var frame = 0
    /// The largest gain reduction applied so far, in dB (0 when nothing was limited).
    private(set) var deepestReductionDb: Float = 0

    init(ceilingDb: Double, sampleRate: Double, channels: Int, lookaheadSeconds: Double = 0.0015, releaseSeconds: Double = 0.08) {
        ceiling = Float(pow(10, ceilingDb / 20))
        self.channels = max(1, channels)
        lookahead = max(1, Int((lookaheadSeconds * sampleRate).rounded()))
        release = Float(1 - exp(-1 / (releaseSeconds * sampleRate)))
        delay = Array(repeating: 0, count: lookahead * self.channels)
        averageRing = Array(repeating: 1, count: lookahead)
        averageSum = Float(lookahead)
    }

    /// Limits `samples` (interleaved, `channels` per frame) in place.
    mutating func process(_ samples: UnsafeMutableBufferPointer<Float>) {
        let frames = samples.count / channels
        for index in 0..<frames {
            let base = index * channels
            var peak: Float = 0
            for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
            let needed = peak > ceiling ? ceiling / peak : 1
            // Running min of the needed gain over the last lookahead + 1 frames.
            while minimumQueue.count > queueStart, minimumQueue[minimumQueue.count - 1].gain >= needed { minimumQueue.removeLast() }
            minimumQueue.append((frame, needed))
            while minimumQueue[queueStart].frame <= frame - lookahead - 1 { queueStart += 1 }
            if queueStart > 1024 {
                minimumQueue.removeFirst(queueStart)
                queueStart = 0
            }
            let minimum = minimumQueue[queueStart].gain
            // Average of the min-filtered gain over lookahead frames: every value in it already includes the peak
            // of the delayed frame, so the average is at most its needed gain.
            averageSum += minimum - averageRing[averageIndex]
            averageRing[averageIndex] = minimum
            averageIndex = (averageIndex + 1) % lookahead
            let smoothed = min(averageSum / Float(lookahead), 1)
            gain = min(smoothed, gain + (1 - gain) * release)
            deepestReductionDb = max(deepestReductionDb, -20 * log10(max(gain, 1e-6)))
            for channel in 0..<channels {
                let slot = delayIndex * channels + channel
                let delayed = delay[slot]
                delay[slot] = samples[base + channel]
                samples[base + channel] = delayed * gain
            }
            delayIndex = (delayIndex + 1) % lookahead
            frame += 1
        }
    }

    /// Limits a reader's float PCM sample buffer in place (the reader must copy sample data, so the memory is ours).
    mutating func process(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, CMBlockBufferIsRangeContiguous(block, atOffset: 0, length: length) else { return }
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &pointer) == noErr,
            let pointer
        else { return }
        pointer.withMemoryRebound(to: Float.self, capacity: length / MemoryLayout<Float>.size) { floats in
            process(UnsafeMutableBufferPointer(start: floats, count: length / MemoryLayout<Float>.size))
        }
    }
}
