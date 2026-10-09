@preconcurrency import AVFoundation
import Foundation
import VideoToolbox

/// Decoders AVFoundation only uses after the app asks for them, and the check for footage this Mac cannot decode.
public enum VideoDecoders {
    /// The codecs macOS ships as supplemental decoders: VP9 (and AV1 on Macs that decode it). Without
    /// registering them AVFoundation opens a VP9 `.mp4` but cannot decode a single frame of it.
    public static let supplemental: [CMVideoCodecType] = [kCMVideoCodecType_VP9, kCMVideoCodecType_AV1]

    private static let registration: Void = {
        for codec in supplemental { VTRegisterSupplementalVideoDecoderIfAvailable(codec) }
    }()

    /// Registers the supplemental decoders once per process. Call before opening media; later calls do nothing.
    public static func enable() { _ = registration }

    /// The four-character code of `track`'s codec when this Mac cannot decode it (VP9 on a Mac without the
    /// decoder, for example), nil when it can.
    public static func undecodableCodec(_ track: AVAssetTrack) async throws -> String? {
        enable()
        guard try await !track.load(.isDecodable) else { return nil }
        let descriptions = try await track.load(.formatDescriptions)
        return fourCC(descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0)
    }

    public static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
    }
}

/// A timeline item shows video this Mac cannot decode: preview shows black there and export refuses.
public struct UndecodableMedia: Sendable, Equatable {
    public let mediaID: String
    public let path: String
    public let codec: String
    /// The timeline frames `start..<end` where an item shows it.
    public let start: Int
    public let end: Int

    public init(mediaID: String, path: String, codec: String, start: Int, end: Int) {
        self.mediaID = mediaID
        self.path = path
        self.codec = codec
        self.start = start
        self.end = end
    }
}

public struct UndecodableMediaError: LocalizedError, Sendable, Equatable {
    public let media: [UndecodableMedia]

    public init(_ media: [UndecodableMedia]) { self.media = media }

    public var errorDescription: String? {
        let names = Dictionary(media.map { ($0.mediaID, "\(URL(fileURLWithPath: $0.path).lastPathComponent) (\($0.codec))") },
                               uniquingKeysWith: { first, _ in first })
        return "This Mac cannot decode the video of " + names.values.sorted().joined(separator: ", ")
            + ". Convert it to H.264 or HEVC and import it again."
    }
}
