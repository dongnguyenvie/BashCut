import BashCutDocument
import BashCutProject
import Foundation

/// Timeline geometry shared by the canvas, the fixed layer header and the overlays: where frames and layers
/// are on screen. The main layer is taller so its clips can show a filmstrip.
@MainActor struct TimelineLayout {
    struct Row {
        let track: Track
        let y: Double
        let height: Double
        var maxY: Double { y + height }
        var rect: CGRect { CGRect(x: 0, y: y, width: 0, height: height) }
    }

    /// Width of the fixed layer header; frame 0 starts here.
    static let leading = EditorUIState.timelineLeading
    static let rulerHeight = 22.0
    static let sectionBand = 24.0...46.0
    static let firstRowY = 52.0
    static let rowSpacing = 6.0
    static let rowHeight = 29.0
    static let mainRowHeight = 46.0
    /// Trailing space after the last frame.
    static let trailing = 100.0

    /// Points per frame.
    let scale: Double
    let rows: [Row]

    init(project: Project, scale: Double) {
        self.scale = scale
        let visual = project.tracks.filter(\.isVisual).reversed()
        let audio = project.tracks.filter { !$0.isVisual }
        var y = Self.firstRowY
        var rows: [Row] = []
        for track in Array(visual) + audio {
            let height = track.role == TrackRole.main ? Self.mainRowHeight : Self.rowHeight
            rows.append(Row(track: track, y: y, height: height))
            y += height + Self.rowSpacing
        }
        self.rows = rows
    }

    /// True when both layouts have the same layers at the same places with the same names and switches; the
    /// clips on them may differ.
    func sameRows(as other: TimelineLayout) -> Bool {
        rows.count == other.rows.count && zip(rows, other.rows).allSatisfy { row, otherRow in
            row.y == otherRow.y && row.height == otherRow.height && row.track.sameSettings(as: otherRow.track)
        }
    }

    var contentHeight: Double { (rows.last?.maxY ?? Self.firstRowY) + Self.rowSpacing }

    func x(_ frame: Int) -> Double { Self.leading + Double(frame) * scale }

    /// The frame under `x`, rounded to the nearest frame and never negative.
    func frame(at x: Double) -> Int { max(0, Int(((x - Self.leading) / scale).rounded())) }

    func row(at y: Double) -> Row? { rows.first { y >= $0.y && y < $0.maxY + Self.rowSpacing } }

    func row(for trackID: String) -> Row? { rows.first { $0.track.id == trackID } }

    func rect(of item: Item, in row: Row) -> CGRect {
        CGRect(x: x(item.at), y: row.y, width: max(3, Double(item.duration) * scale - 2), height: row.height)
    }

    func rect(ofGap gap: Range<Int>, in row: Row) -> CGRect {
        CGRect(x: x(gap.lowerBound), y: row.y, width: Double(gap.count) * scale - 2, height: row.height)
    }
}

/// `mm:ss:ff` (or `h:mm:ss:ff` past an hour) for timeline labels.
enum Timecode {
    static func string(_ frame: Int, fps: FrameRate) -> String {
        let rate = max(1, Int(fps.value.rounded()))
        let frames = max(0, frame)
        let totalSeconds = Int(Double(frames) / fps.value)
        let remainder = frames - Int((Double(totalSeconds) * fps.value).rounded(.down))
        let (hours, minutes, seconds) = (totalSeconds / 3600, totalSeconds / 60 % 60, totalSeconds % 60)
        let tail = String(format: "%02d:%02d:%02d", minutes, seconds, min(rate - 1, max(0, remainder)))
        return hours > 0 ? "\(hours):" + tail : tail
    }

    /// A signed frame difference, e.g. `+00:00:15` or `-00:01:02`.
    static func delta(_ frames: Int, fps: FrameRate) -> String {
        (frames < 0 ? "-" : "+") + string(abs(frames), fps: fps)
    }

    /// `3.2s` style durations for clip badges.
    static func duration(_ frames: Int, fps: FrameRate) -> String {
        let seconds = Double(frames) / fps.value
        return seconds >= 60
            ? String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
            : String(format: "%.1fs", seconds)
    }
}
