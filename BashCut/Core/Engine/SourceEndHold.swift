@preconcurrency import AVFoundation

extension AVMutableCompositionTrack {
    /// Inserts `range` of `source` stretched over `target`. `Media.frames` comes from the file's
    /// duration, which can run past the last picture (audio longer than video); the share of `range` past
    /// `available`'s end holds the last picture (`frame` long) instead of leaving the compositor without a frame.
    func insertHoldingEnd(
        _ range: CMTimeRange, of source: AVAssetTrack, available: CMTimeRange?, frame: CMTime, over target: CMTimeRange
    ) throws {
        guard let available, range.end > available.end, available.duration > .zero else {
            try insertTimeRange(range, of: source, at: target.start)
            scaleTimeRange(CMTimeRange(start: target.start, duration: range.duration), toDuration: target.duration)
            return
        }
        var rest = target
        if available.end > range.start {
            let played = CMTimeRange(start: range.start, end: available.end)
            let share = CMTimeMultiplyByFloat64(target.duration, multiplier: played.duration.seconds / range.duration.seconds)
            try insertTimeRange(played, of: source, at: target.start)
            scaleTimeRange(CMTimeRange(start: target.start, duration: played.duration), toDuration: share)
            rest = CMTimeRange(start: target.start + share, end: target.end)
        }
        guard rest.duration > .zero else { return }
        let last = CMTimeRange(start: max(available.start, available.end - frame), end: available.end)
        try insertTimeRange(last, of: source, at: rest.start)
        scaleTimeRange(CMTimeRange(start: rest.start, duration: last.duration), toDuration: rest.duration)
    }
}
