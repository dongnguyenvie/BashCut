import Foundation

/// A measured record of one source file (`media.analyze`, P0-A1): file facts, picture samples with cut candidates,
/// and sound levels. It holds raw measurements only; `media.analysis` derives shots, statistics and sound spans
/// from them with the limits the agent asks for, so a record is measured once and read many ways. Records are kept
/// by `key`, a hash of the file's content, so a moved or renamed file keeps its record and a changed one is measured
/// again. The agent's cut corrections live in the record and go with it.
public struct MediaAnalysis: Codable, Sendable, Equatable {
    /// Bumped when the measurement changes, so older records are measured again.
    public static let version = 1
    public static var measuredBy: String { "bashcut media.analyze v\(version)" }

    public struct Video: Codable, Sendable, Equatable {
        public var codec: String?
        public var width: Int
        public var height: Int
        /// Degrees the picture is turned on playback (the track's preferred transform).
        public var rotation: Int
        public var nominalFPS: Double
        public var seconds: Double
        /// Presentation-time statistics of the video samples, in seconds; nil when the samples could not be read.
        public var frames: Int?
        public var minFrameSeconds: Double?
        public var maxFrameSeconds: Double?
        public var meanFrameSeconds: Double?
        public var transfer: String?
        public var primaries: String?
        public var matrix: String?
        public var bitDepth: Int?

        public init(
            codec: String? = nil, width: Int, height: Int, rotation: Int = 0, nominalFPS: Double, seconds: Double,
            frames: Int? = nil, minFrameSeconds: Double? = nil, maxFrameSeconds: Double? = nil,
            meanFrameSeconds: Double? = nil, transfer: String? = nil, primaries: String? = nil, matrix: String? = nil,
            bitDepth: Int? = nil
        ) {
            (self.codec, self.width, self.height, self.rotation) = (codec, width, height, rotation)
            (self.nominalFPS, self.seconds, self.frames) = (nominalFPS, seconds, frames)
            (self.minFrameSeconds, self.maxFrameSeconds, self.meanFrameSeconds) =
                (minFrameSeconds, maxFrameSeconds, meanFrameSeconds)
            (self.transfer, self.primaries, self.matrix, self.bitDepth) = (transfer, primaries, matrix, bitDepth)
        }
    }

    public struct SoundTrack: Codable, Sendable, Equatable {
        public var codec: String?
        public var channels: Int
        public var sampleRate: Double
        public var seconds: Double

        public init(codec: String? = nil, channels: Int, sampleRate: Double, seconds: Double) {
            (self.codec, self.channels, self.sampleRate, self.seconds) = (codec, channels, sampleRate, seconds)
        }
    }

    /// File facts from the container and track headers.
    public struct Tech: Codable, Sendable, Equatable {
        public var seconds: Double
        public var bytes: Int?
        public var video: Video?
        public var audio: SoundTrack?

        public init(seconds: Double, bytes: Int? = nil, video: Video? = nil, audio: SoundTrack? = nil) {
            (self.seconds, self.bytes, self.video, self.audio) = (seconds, bytes, video, audio)
        }
    }

    public struct Sample: Codable, Sendable, Equatable {
        /// Source frame, at `Picture.fps`.
        public var frame: Int
        /// The `review.picture` values on the same 24×24 grey thumbnail: mean brightness, its spread, the mean
        /// and largest one-cell difference from the previous sample.
        public var luma: Double
        public var spread: Double
        public var change: Double
        public var peak: Double
        /// Mean absolute Laplacian of the grey frame (fraction of full scale): fine detail and focus. Compare within
        /// one file or files of one size.
        public var sharpness: Double
        /// Hasler–Süsstrunk colourfulness on a small RGB thumbnail (fraction of full scale): 0 for grey.
        public var colourfulness: Double

        public init(
            frame: Int, luma: Double, spread: Double, change: Double, peak: Double, sharpness: Double,
            colourfulness: Double
        ) {
            (self.frame, self.luma, self.spread, self.change, self.peak) = (frame, luma, spread, change, peak)
            (self.sharpness, self.colourfulness) = (sharpness, colourfulness)
        }
    }

    /// A possible hard cut: `frame` is the first frame after it, `score` the mean absolute difference between that
    /// frame and the one before (the `cutDifference` of `review.shots`).
    public struct Cut: Codable, Sendable, Equatable {
        public var frame: Int
        public var score: Double

        public init(frame: Int, score: Double) { (self.frame, self.score) = (frame, score) }
    }

    public struct Picture: Codable, Sendable, Equatable {
        public var fps: Double
        /// Source frames between samples.
        public var interval: Int
        /// Frames in the file at `fps`.
        public var frames: Int
        /// `original` or `proxy`: the file the frames were read from (same timing).
        public var source: String
        public var samples: [Sample]
        /// Every sample-to-sample jump of at least `candidateFloor`, narrowed to the exact frame pair.
        public var candidates: [Cut]
        public var candidateFloor: Double

        public init(
            fps: Double, interval: Int, frames: Int, source: String = "original", samples: [Sample],
            candidates: [Cut], candidateFloor: Double
        ) {
            (self.fps, self.interval, self.frames, self.source) = (fps, max(1, interval), frames, source)
            (self.samples, self.candidates, self.candidateFloor) = (samples, candidates, candidateFloor)
        }
    }

    public struct Sound: Codable, Sendable, Equatable {
        /// Seconds per level window.
        public var window: Double
        /// RMS level of each window over all channels, dBFS; digital silence reads `silenceDb`.
        public var levels: [Double]
        /// Largest sample, dBFS.
        public var peakDb: Double
        /// Correlation of the first two channels over the file (1 mono-like, 0 unrelated, below 0 out of phase);
        /// nil for one channel.
        public var stereoCorrelation: Double?

        public init(window: Double, levels: [Double], peakDb: Double, stereoCorrelation: Double? = nil) {
            (self.window, self.levels, self.peakDb, self.stereoCorrelation) = (window, levels, peakDb, stereoCorrelation)
        }
    }

    /// Cut corrections by the agent, in source frames: cuts to add, and candidates to drop (matched within one
    /// sample interval).
    public struct Corrections: Codable, Sendable, Equatable {
        public var add: [Int]
        public var remove: [Int]

        public init(add: [Int] = [], remove: [Int] = []) { (self.add, self.remove) = (add, remove) }
        public var isEmpty: Bool { add.isEmpty && remove.isEmpty }
    }

    public static let silenceDb = -120.0

    public var version: Int
    public var key: String
    public var measuredBy: String
    /// ISO 8601.
    public var measuredAt: String
    public var tech: Tech
    public var picture: Picture?
    public var sound: Sound?
    public var corrections: Corrections

    public init(
        key: String, measuredAt: String, tech: Tech, picture: Picture? = nil, sound: Sound? = nil,
        corrections: Corrections = Corrections()
    ) {
        version = Self.version
        measuredBy = Self.measuredBy
        (self.key, self.measuredAt, self.tech, self.picture, self.sound, self.corrections) =
            (key, measuredAt, tech, picture, sound, corrections)
    }
}
