@preconcurrency import AVFoundation
import BashCutProject

/// How many source frames a file offers. A video's count ends at its last picture, not at the container duration:
/// camera files often carry sound past the last picture, and counting those frames offered timeline frames with no
/// picture (#420, #437).
public enum MediaFrames {
    /// Source frames of `asset` at `fps`: up to the end of the video track's last picture when there is one,
    /// otherwise up to the container duration.
    public static func sourceFrames(of asset: AVURLAsset, fps: FrameRate) async throws -> Int {
        let duration = try await asset.load(.duration)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return Int((duration.seconds * fps.value).rounded(.down)) }
        let end = min(try await pictureRange(video).end, duration)
        // A tolerance for the picture end landing a hair under a whole frame (60 × 1001/30000 s at 29.97 fps).
        return Int((end.seconds * fps.value + 0.001).rounded(.down))
    }

    /// From the first to the last picture: an empty edit (sound before the first picture) is part of `timeRange`.
    static func pictureRange(_ track: AVAssetTrack) async throws -> CMTimeRange {
        let pictures = try await track.load(.segments).filter { !$0.isEmpty }.map(\.timeMapping.target)
        guard let first = pictures.first, let last = pictures.last else { return try await track.load(.timeRange) }
        return CMTimeRange(start: first.start, end: last.end)
    }
}
