@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// Writes part of a sound file to a new file (saving a trimmed audio clip to the library): PCM stays PCM in a WAV
/// file at the source's bit depth, compressed sound is written as AAC in an M4A file.
public enum AudioRangeWriter {
    /// The extension the copy of `source` gets: `wav` for an uncompressed file, `m4a` otherwise.
    public static func outputExtension(for source: URL) throws -> String {
        let file = try AVAudioFile(forReading: source)
        return isPCM(file) ? "wav" : "m4a"
    }

    /// Writes seconds `range` of `source` to `destination` (whose extension should be `outputExtension(for:)`): a
    /// `.wav` as PCM at the source's bit depth, anything else as AAC. Returns the seconds written; throws when the range
    /// holds no sound.
    @discardableResult
    public static func write(source: URL, range: ClosedRange<Double>, to destination: URL) throws -> Double {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let rate = format.sampleRate
        let first = AVAudioFramePosition(max(0, range.lowerBound) * rate)
        let last = min(input.length, AVAudioFramePosition((range.upperBound * rate).rounded()))
        guard last > first else { throw ProjectError.invalid("\(source.lastPathComponent): the range holds no sound") }
        var settings = input.fileFormat.settings
        // An AIFF source is big-endian; WAV is little-endian.
        settings[AVLinearPCMIsBigEndianKey] = false
        settings[AVLinearPCMIsNonInterleaved] = false
        if destination.pathExtension.lowercased() != "wav" {
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 256_000,
            ]
        }
        try? FileManager.default.removeItem(at: destination)
        let output = try AVAudioFile(
            forWriting: destination, settings: settings, commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw ProjectError.invalid("Could not allocate an audio buffer")
        }
        input.framePosition = first
        var remaining = last - first
        while remaining > 0 {
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining)))
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        return Double(last - first - max(0, remaining)) / rate
    }

    private static func isPCM(_ file: AVAudioFile) -> Bool {
        (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM
    }
}
