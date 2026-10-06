@preconcurrency import AVFoundation

extension AVMutableCompositionTrack {
    /// Inserts `range` of `source` stretched over `target`. `Media.frames` of media imported before #437 comes from
    /// the file's duration, and camera files often have sound before the first picture or after the last one; the
    /// share of `range` outside `available` holds the first or last picture (`frame` long) instead of leaving the compositor without a frame.
    func insertHoldingEdges(
        _ range: CMTimeRange, of source: AVAssetTrack, available: CMTimeRange?, frame: CMTime, over target: CMTimeRange
    ) throws {
        guard let available, available.duration > .zero,
              range.start < available.start || range.end > available.end
        else {
            try insert(range, of: source, over: target)
            return
        }
        let first = CMTimeRange(start: available.start, duration: min(frame, available.duration))
        let last = CMTimeRange(start: max(available.start, available.end - frame), end: available.end)
        let inside = CMTimeRange(start: max(range.start, available.start), end: min(range.end, available.end))
        // Split points on the target's own time scale, so the parts end exactly at `target.end`; a split rounded to
        // nanoseconds left the composition a fraction longer than its instructions (AVError -11841).
        func point(_ time: CMTime) -> CMTime {
            let fraction = min(1, max(0, (time - range.start).seconds / range.duration.seconds))
            let offset = CMTimeConvertScale(
                CMTimeMultiplyByFloat64(target.duration, multiplier: fraction),
                timescale: target.duration.timescale, method: .roundHalfAwayFromZero)
            return target.start + offset
        }
        let insideStart = inside.duration > .zero ? point(inside.start) : point(min(range.end, available.start))
        let insideEnd = inside.duration > .zero ? point(inside.end) : insideStart
        let parts = [
            (first, CMTimeRange(start: target.start, end: insideStart)),
            (inside, CMTimeRange(start: insideStart, end: insideEnd)),
            (last, CMTimeRange(start: insideEnd, end: target.end)),
        ]
        for (piece, part) in parts where piece.duration > .zero && part.duration > .zero {
            try insert(piece, of: source, over: part)
        }
    }

    private func insert(_ range: CMTimeRange, of source: AVAssetTrack, over target: CMTimeRange) throws {
        try insertTimeRange(range, of: source, at: target.start)
        scaleTimeRange(CMTimeRange(start: target.start, duration: range.duration), toDuration: target.duration)
    }
}
