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
    /// Width of the fixed layer header (`EditorUIState.timelineLeading`); frame 0 starts here.
    let leading: Double
    let rows: [Row]
    /// Each layer's short ID (V1, A1) by track ID.
    let labels: [String: String]

    init(project: Project, scale: Double, leading: Double = EditorUIState.compactTimelineLeading) {
        self.scale = scale
        self.leading = leading
        labels = project.trackLabels
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
        leading == other.leading && labels == other.labels && rows.count == other.rows.count && zip(rows, other.rows).allSatisfy { row, otherRow in
            row.y == otherRow.y && row.height == otherRow.height && row.track.sameSettings(as: otherRow.track)
        }
    }

    var contentHeight: Double { (rows.last?.maxY ?? Self.firstRowY) + Self.rowSpacing }

    func x(_ frame: Int) -> Double { leading + Double(frame) * scale }

    /// The frame under `x`, rounded to the nearest frame and never negative.
    func frame(at x: Double) -> Int { max(0, Int(((x - leading) / scale).rounded())) }

    func row(at y: Double) -> Row? { rows.first { y >= $0.y && y < $0.maxY + Self.rowSpacing } }

    func row(for trackID: String) -> Row? { rows.first { $0.track.id == trackID } }

    func rect(of item: Item, in row: Row) -> CGRect {
        CGRect(x: x(item.at), y: row.y, width: max(3, Double(item.duration) * scale - 2), height: row.height)
    }

    func rect(ofGap gap: Range<Int>, in row: Row) -> CGRect {
        CGRect(x: x(gap.lowerBound), y: row.y, width: Double(gap.count) * scale - 2, height: row.height)
    }
}
