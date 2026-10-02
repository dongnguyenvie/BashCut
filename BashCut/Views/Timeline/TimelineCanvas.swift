import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject

/// The scrolling timeline: ruler, section band, beat grid and clips. The playhead, drag guides and labels are
/// separate overlay views, so scrubbing and playback move them without redrawing clips; the canvas redraws only
/// when its content changes (see `TimelineView`).
@MainActor final class TimelineCanvas: NSView {
    let document: ProjectDocument
    var project: Project {
        didSet { mediaByID = Self.index(project.media) }
    }
    /// Project media by ID, so drawing each clip does not search the media list.
    private(set) var mediaByID: [String: Media] = [:]
    var layout: TimelineLayout
    var waveforms: [String: AudioWaveform] = [:]
    var selectedID: String?
    var playhead = 0
    var lastReveal: TimelineReveal?
    var lastZoomAnchor: TimelineZoomAnchor?
    var lastContent: TimelineView.ContentKey?
    var voiceoverWarningIDs: Set<String> = []
    var reviewRevision = -1

    /// The clip under the pointer, drawn highlighted with trim handles.
    var hoveredItemID: String? {
        didSet { if hoveredItemID != oldValue { redrawItems([oldValue, hoveredItemID]) } }
    }
    /// A gap on a layer the user clicked; Delete closes it.
    var selectedGap: (trackID: String, range: Range<Int>)? {
        didSet { needsDisplay = true }
    }

    // Gesture state.
    enum Gesture {
        case playhead
        case section(TimelineMarker)
        case clip(ClipDrag)
    }
    struct ClipDrag {
        let item: Item
        let track: Track
        let origin: CGPoint
        let edge: BashCutProject.Edge?
        let rolling: Bool
        let slipping: Bool
    }
    var gesture: Gesture?
    var isScrubbing: Bool {
        if case .playhead = gesture { return true }
        return false
    }
    var hoverCursor = NSCursor.arrow
    var filmstripURLs: [String: URL?] = [:]
    var dragFrame: Int?
    var slipSourceIn: Int?
    var dragRevision = 0

    // Overlays.
    let playheadView = PlayheadView(frame: .zero)
    let dropGuide = GuideLineView(color: .systemCyan)
    let snapGuide = GuideLineView(color: .systemYellow)
    let badge = TimelineBadgeView(frame: .zero)
    let ghost = ClipGhostView(frame: .zero)
    let filmstrips = FilmstripCache()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var scale: Double { layout.scale }

    init(document: ProjectDocument) {
        self.document = document
        project = document.project
        layout = TimelineLayout(project: document.project, scale: 1)
        mediaByID = Self.index(document.project.media)
        super.init(frame: .zero)
        wantsLayer = true
        for overlay in [ghost, dropGuide, snapGuide, playheadView, badge] as [NSView] { addSubview(overlay) }
        filmstrips.onUpdate = { [weak self] in self?.redrawFilmstrips() }
        registerForDraggedTypes([.string, .fileURL])
    }
    required init?(coder: NSCoder) { nil }

    /// Moves the playhead overlay; cheap enough for every playback frame and pointer event.
    func placePlayhead(_ frame: Int) {
        playhead = frame
        playheadView.place(atX: layout.x(frame), height: bounds.height)
    }

    private static func index(_ media: [Media]) -> [String: Media] {
        Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// New thumbnails landed: redraw the visible part of the layers that show a filmstrip, not the whole canvas.
    func redrawFilmstrips() {
        for row in layout.rows where row.track.kind == "video" && row.height >= TimelineLayout.mainRowHeight {
            let rect = CGRect(x: 0, y: row.y, width: bounds.width, height: row.height).intersection(visibleRect)
            if !rect.isEmpty { setNeedsDisplay(rect) }
        }
    }

    func redrawItems(_ ids: [String?]) {
        for id in ids.compactMap({ $0 }) {
            guard let (rect, _, _) = locate(id) else { continue }
            setNeedsDisplay(rect.insetBy(dx: -8, dy: -2))
        }
    }

    func locate(_ itemID: String) -> (CGRect, Item, Track)? {
        for row in layout.rows {
            if let item = row.track.items.first(where: { $0.id == itemID }) {
                return (layout.rect(of: item, in: row), item, row.track)
            }
        }
        return nil
    }

    func hit(at point: CGPoint) -> (CGRect, Item, Track)? {
        guard let row = layout.row(at: point.y) else { return nil }
        for item in row.track.items.reversed() {
            let rect = layout.rect(of: item, in: row)
            if rect.contains(point) { return (rect, item, row.track) }
        }
        return nil
    }

    /// The gap under `point` on a layer that has clips after it.
    func gapHit(at point: CGPoint) -> (trackID: String, range: Range<Int>)? {
        guard let row = layout.row(at: point.y), point.y < row.maxY, point.x >= TimelineLayout.leading else { return nil }
        let frame = Int((point.x - TimelineLayout.leading) / scale)
        return row.track.gaps.first { $0.contains(frame) }.map { (row.track.id, $0) }
    }

    func sectionHit(at point: CGPoint) -> TimelineMarker? {
        guard TimelineLayout.sectionBand.contains(point.y) else { return nil }
        return project.sectionMarkers.min { abs(layout.x($0.at) - point.x) < abs(layout.x($1.at) - point.x) }
            .flatMap { abs(layout.x($0.at) - point.x) <= 7 ? $0 : nil }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
        dirtyRect.intersection(bounds).fill()
        drawRuler(dirtyRect)
        drawSectionBand(dirtyRect)
        drawBeatGrid(dirtyRect)
        let root = document.fileURL?.deletingLastPathComponent()
        for row in layout.rows {
            let rowRect = CGRect(x: 0, y: row.y, width: bounds.width, height: row.height)
            guard rowRect.intersects(dirtyRect) else { continue }
            if row.track.id == document.selectedTrackID {
                NSColor.systemCyan.withAlphaComponent(0.06).setFill()
                rowRect.fill()
            }
            drawGaps(in: row, dirtyRect: dirtyRect)
            for item in row.track.items {
                let rect = layout.rect(of: item, in: row)
                guard rect.intersects(dirtyRect) else { continue }
                drawClip(item, in: rect, row: row, dirtyRect: dirtyRect, root: root)
            }
        }
    }

    private func drawSectionBand(_ dirtyRect: CGRect) {
        let sections = project.sectionMarkers
        let bandY = TimelineLayout.sectionBand
        let band = CGRect(
            x: TimelineLayout.leading, y: bandY.lowerBound, width: max(0, bounds.width - TimelineLayout.leading),
            height: bandY.upperBound - bandY.lowerBound)
        guard band.intersects(dirtyRect) else { return }
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        band.fill()
        for (index, marker) in sections.enumerated() {
            let end = index + 1 < sections.count ? sections[index + 1].at : project.duration
            let rect = CGRect(
                x: layout.x(marker.at), y: band.minY + 1, width: max(3, Double(max(marker.at, end) - marker.at) * scale - 1),
                height: band.height - 2)
            guard rect.intersects(dirtyRect) else { continue }
            (index.isMultiple(of: 2) ? NSColor.systemIndigo : NSColor.systemPurple).withAlphaComponent(0.42).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            (marker.label as NSString).draw(in: rect.insetBy(dx: 5, dy: 3), withAttributes: ClipStyle.sectionText)
        }
    }

    private func drawBeatGrid(_ dirtyRect: CGRect) {
        let lines = NSBezierPath()
        for frame in project.beatFrames {
            let x = layout.x(frame)
            guard x >= dirtyRect.minX, x <= dirtyRect.maxX else { continue }
            lines.move(to: CGPoint(x: x, y: TimelineLayout.sectionBand.upperBound + 1))
            lines.line(to: CGPoint(x: x, y: bounds.height))
        }
        NSColor.systemOrange.withAlphaComponent(0.28).setStroke()
        lines.stroke()
    }

    private func drawGaps(in row: TimelineLayout.Row, dirtyRect: CGRect) {
        guard row.track.role == TrackRole.main else { return }
        for gap in row.track.gaps {
            let rect = CGRect(x: layout.x(gap.lowerBound), y: row.y, width: Double(gap.count) * scale - 2, height: row.height)
            guard rect.width > 2, rect.intersects(dirtyRect) else { continue }
            let selected = selectedGap?.trackID == row.track.id && selectedGap?.range == gap
            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            path.addClip()
            NSColor(calibratedWhite: 1, alpha: selected ? 0.12 : 0.05).setStroke()
            let stripes = NSBezierPath()
            stride(from: rect.minX - rect.height, through: rect.maxX, by: 8).forEach { x in
                stripes.move(to: CGPoint(x: x, y: rect.maxY))
                stripes.line(to: CGPoint(x: x + rect.height, y: rect.minY))
            }
            stripes.stroke()
            NSGraphicsContext.restoreGraphicsState()
            if selected {
                NSColor.white.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 1.5
                path.stroke()
                if rect.width > 70 {
                    ("Gap " + Timecode.duration(gap.count, fps: project.fps) as NSString)
                        .draw(at: CGPoint(x: rect.minX + 6, y: rect.midY - 6), withAttributes: ClipStyle.durationText)
                }
            }
        }
    }
}
