import AVFoundation
import Foundation

/// Shared fixtures for every app-module test target: the generated media folder, scratch folders and
/// synthetic audio. Tests never read real workspace files (see AGENTS.md).
public enum TestFixtures {
    public struct Missing: Error, CustomStringConvertible {
        public let description: String
    }

    /// The repository root, found from this file's location (`Tests/BashCutTestSupport/TestFixtures.swift`).
    public static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// `Fixtures/media`, filled by `Fixtures/make-media.sh`.
    public static let mediaRoot = repositoryRoot.appendingPathComponent("Fixtures/media", isDirectory: true)

    /// The generated 2 s, 320×180, 29.97 fps H.264/AAC clip (`test.mp4`, 59 frames).
    public static let videoURL = mediaRoot.appendingPathComponent("test.mp4")

    /// `videoURL`, or a clear error when `Fixtures/make-media.sh` has not been run.
    public static func requireVideo() throws -> URL {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw Missing(description: "Run Fixtures/make-media.sh before engine integration tests")
        }
        return videoURL
    }

    /// A new, empty folder under the temporary directory. Callers remove it when they care about cleanup.
    public static func temporaryDirectory(_ prefix: String = "bashcut") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a sine tone as a PCM file. Channel 2 (if any) carries the opposite phase, and samples from
    /// `silentAfter` seconds on are zero.
    public static func writeTone(
        to url: URL, seconds: Double, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 1,
        tone: Tone = Tone()
    ) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * sampleRate)),
              let data = buffer.floatChannelData
        else { throw Missing(description: "Cannot allocate a \(channels)-channel audio buffer") }
        buffer.frameLength = buffer.frameCapacity
        let silentFrom = tone.silentAfter.map { Int($0 * sampleRate) } ?? Int.max
        for index in 0..<Int(buffer.frameLength) {
            let phase = 2 * Double.pi * tone.frequency * Double(index) / sampleRate
            let value = index < silentFrom ? Float(sin(phase)) * tone.amplitude : 0
            data[0][index] = value
            if channels > 1 { data[1][index] = -value }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    public struct Tone: Sendable {
        public var frequency: Double
        public var amplitude: Float
        public var silentAfter: Double?

        public init(frequency: Double = 400, amplitude: Float = 0.2, silentAfter: Double? = nil) {
            self.frequency = frequency
            self.amplitude = amplitude
            self.silentAfter = silentAfter
        }
    }
}
