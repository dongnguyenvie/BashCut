@preconcurrency import AVFoundation
import Accelerate
import BashCutProject

/// Waveform-similarity overlap-add with bounded source-position search, shared across all channels.
/// See Driedger/Müller, A Review of Time-Scale Modification of Music Signals (2016), §4.
/// A 2048-sample window, 256-sample hop and ±480-sample alignment search keep transients local at 48 kHz.
enum WaveformAudioRamp {
    private static let window = 2048
    private static let hop = 256
    private static let search = 480

    static func render(input url: URL, output: URL, curve: SpeedCurve, seconds: Double, check: () throws -> Void) throws {
        let source = try SampleWindow(url)
        let file = try AVAudioFile(forWriting: output, settings: source.format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(hop)),
              let data = buffer.floatChannelData else { throw ProjectError.invalid("Could not allocate ramp output") }
        let total = Int(ceil(seconds * source.format.sampleRate))
        let channels = Int(source.format.channelCount)
        var accumulation = Array(repeating: [Float](repeating: 0, count: window), count: channels)
        var weights = [Float](repeating: 0, count: window)
        let envelope = (0..<window).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(window))) }
        var previous: [[Float]]?
        for start in stride(from: -window + hop, to: total, by: hop) {
            try check()
            let center = Double(start + window / 2)
            let fraction = center / (seconds * source.format.sampleRate)
            let position: Double
            if fraction < 0 {
                position = center * curve.points[0].speed
            } else if fraction > 1 {
                position = curve.average * seconds * source.format.sampleRate
                    + (center - seconds * source.format.sampleRate) * curve.points[curve.points.count - 1].speed
            } else {
                position = curve.integral(to: fraction) * seconds * source.format.sampleRate
            }
            let nominal = Int(position.rounded()) - window / 2
            let candidates = try source.read(from: nominal - search, count: window + 2 * search)
            let offset = previous.map { alignment(previous: $0, candidates: candidates) } ?? search
            let grain = candidates.map { Array($0[offset..<(offset + window)]) }
            for index in 0..<window {
                weights[index] += envelope[index]
                for channel in 0..<channels { accumulation[channel][index] += grain[channel][index] * envelope[index] }
            }
            let lower = max(0, -start), upper = min(hop, total - start)
            if upper > lower {
                buffer.frameLength = AVAudioFrameCount(upper - lower)
                for channel in 0..<channels {
                    for index in lower..<upper { data[channel][index - lower] = accumulation[channel][index] / max(weights[index], 1e-8) }
                }
                try file.write(from: buffer)
            }
            for channel in 0..<channels {
                accumulation[channel].removeFirst(hop)
                accumulation[channel].append(contentsOf: repeatElement(0, count: hop))
            }
            weights.removeFirst(hop)
            weights.append(contentsOf: repeatElement(0, count: hop))
            previous = grain
        }
    }

    private static func alignment(previous: [[Float]], candidates: [[Float]]) -> Int {
        let overlap = window - hop
        // Choose the strongest channel; summing anti-phase stereo channels would erase the correlation signal.
        let energies = previous.map { channel in channel[hop...].reduce(Float(0)) { $0 + $1 * $1 } }
        guard let channel = energies.indices.max(by: { energies[$0] < energies[$1] }), energies[channel] > 1e-8 else { return search }
        let reference = Array(previous[channel][hop...])
        return reference.withUnsafeBufferPointer { reference in
            candidates[channel].withUnsafeBufferPointer { candidate in
                guard let left = reference.baseAddress, let right = candidate.baseAddress else { return search }
                func score(_ offset: Int) -> Float {
                    var dot: Float = 0, energy: Float = 0
                    vDSP_dotpr(left, 1, right + offset, 1, &dot, vDSP_Length(overlap))
                    vDSP_svesq(right + offset, 1, &energy, vDSP_Length(overlap))
                    guard energy > 1e-8 else { return -Float.infinity }
                    return dot / sqrt(energy * energies[channel]) - Float(abs(offset - search)) * 1e-7
                }
                var best = search, bestScore = score(search)
                for offset in stride(from: 0, through: 2 * search, by: 4) {
                    let value = score(offset)
                    if value > bestScore { best = offset; bestScore = value }
                }
                for offset in max(0, best - 4)...min(2 * search, best + 4) {
                    let value = score(offset)
                    if value > bestScore { best = offset; bestScore = value }
                }
                return best
            }
        }
    }
}

/// Bounded PCM read-ahead; a long clip never needs a whole-file sample array in memory.
private final class SampleWindow {
    let format: AVAudioFormat
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private var start = -1
    private var length = 0

    init(_ url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw ProjectError.invalid("Could not allocate ramp input")
        }
        self.buffer = buffer
    }

    func read(from requested: Int, count: Int) throws -> [[Float]] {
        let lower = max(0, requested), upper = min(Int(file.length), requested + count)
        var result = Array(repeating: [Float](repeating: 0, count: count), count: Int(format.channelCount))
        guard upper > lower else { return result }
        if start < 0 || lower < start || upper > start + length {
            start = max(0, lower - 512)
            file.framePosition = AVAudioFramePosition(start)
            try file.read(into: buffer)
            length = Int(buffer.frameLength)
        }
        guard let data = buffer.floatChannelData, upper <= start + length else { throw ProjectError.invalid("Could not read ramp window") }
        for channel in result.indices {
            for frame in lower..<upper { result[channel][frame - requested] = data[channel][frame - start] }
        }
        return result
    }
}
