import BashCutProject
import Foundation

/// `mm:ss:ff` (or `h:mm:ss:ff` past an hour) for timeline labels.
public enum Timecode {
    public static func string(_ frame: Int, fps: FrameRate) -> String {
        let rate = max(1, Int(fps.value.rounded()))
        let frames = max(0, frame)
        let totalSeconds = Int(Double(frames) / fps.value)
        let remainder = frames - Int((Double(totalSeconds) * fps.value).rounded(.down))
        let (hours, minutes, seconds) = (totalSeconds / 3600, totalSeconds / 60 % 60, totalSeconds % 60)
        let tail = String(format: "%02d:%02d:%02d", minutes, seconds, min(rate - 1, max(0, remainder)))
        return hours > 0 ? "\(hours):" + tail : tail
    }

    /// A signed frame difference, e.g. `+00:00:15` or `-00:01:02`.
    public static func delta(_ frames: Int, fps: FrameRate) -> String {
        (frames < 0 ? "-" : "+") + string(abs(frames), fps: fps)
    }

    /// `3.2s` style durations for clip badges.
    public static func duration(_ frames: Int, fps: FrameRate) -> String {
        let seconds = Double(frames) / fps.value
        return seconds >= 60
            ? String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
            : String(format: "%.1fs", seconds)
    }

    /// The transport label under both viewers: playhead and length in the timeline's format,
    /// e.g. `00:00:00 / 00:50:15`.
    public static func transportLabel(position: Int, length: Int, fps: FrameRate) -> String {
        string(position, fps: fps) + " / " + string(length, fps: fps)
    }
}
