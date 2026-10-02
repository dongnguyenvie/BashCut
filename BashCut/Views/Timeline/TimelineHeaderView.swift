import AppKit
import BashCutProject

/// The layer header pinned to the left edge of the timeline while it scrolls sideways: the current time over
/// the ruler, then per layer an icon, its name and switches (hide for visual layers, mute for audio layers,
/// lock for all). Clicking a row selects the layer.
final class TimelineHeaderView: NSView {
    enum Switch { case hidden, muted, locked }

    var layout = TimelineLayout(project: Project(name: ""), scale: 1) { didSet { needsDisplay = true } }
    var selectedTrackID: String? { didSet { if selectedTrackID != oldValue { needsDisplay = true } } }
    /// The playhead time over the ruler. A subview of its own, so playback redraws only this label.
    let time = TimelineTimeLabel(
        frame: NSRect(x: 0, y: 0, width: TimelineLayout.leading - 1, height: TimelineLayout.rulerHeight))
    /// Vertical scroll offset of the timeline; content is drawn shifted up by it (bounds never move, so nothing
    /// is drawn outside the view).
    var scrollOffset = 0.0 {
        didSet {
            guard scrollOffset != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onSelect: ((String) -> Void)?
    var onToggle: ((String, Switch) -> Void)?
    /// The context menu for a layer row (plugin `track.context` actions); the row is selected first.
    var onMenu: ((String) -> NSMenu?)?

    private static let buttonSize = 18.0
    private static var symbols: [String: NSImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(time)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Fill only inside our bounds: AppKit may hand this overlay a dirty rect larger than the view, and a
        // copy-mode fill there paints over the sibling SwiftUI views.
        let visible = dirtyRect.intersection(bounds)
        guard !visible.isNull else { return }
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill()
        visible.fill()
        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill(using: .sourceOver)
        NSBezierPath(rect: bounds).setClip()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: -scrollOffset)
        shift.concat()
        let area = visible.offsetBy(dx: 0, dy: scrollOffset)
        ("Sections" as NSString).draw(
            at: NSPoint(x: 8, y: TimelineLayout.sectionBand.lowerBound + 4),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
        for row in layout.rows where NSRect(x: 0, y: row.y, width: bounds.width, height: row.height).intersects(area) {
            draw(row)
        }
    }

    private func draw(_ row: TimelineLayout.Row) {
        let track = row.track
        let rect = NSRect(x: 0, y: row.y, width: bounds.width - 1, height: row.height)
        (track.id == selectedTrackID ? NSColor.systemCyan.withAlphaComponent(0.16) : NSColor(calibratedWhite: 0.13, alpha: 1))
            .setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 0), xRadius: 4, yRadius: 4).fill()
        let dimmed = track.isHidden || track.isMuted
        let centerY = row.y + row.height / 2
        Self.symbol(Self.icon(for: track), tint: dimmed ? .tertiaryLabelColor : .secondaryLabelColor)?
            .draw(in: NSRect(x: 8, y: centerY - 7, width: 14, height: 14))
        let nameWidth = bounds.width - 30 - 2 * Self.buttonSize - 8
        (track.name as NSString).draw(
            with: NSRect(x: 26, y: centerY - 7, width: nameWidth, height: 14),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: track.role == TrackRole.main ? .semibold : .regular),
                .foregroundColor: dimmed ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            ])
        for (kind, frame) in buttons(for: row) {
            let (name, active) = Self.switchSymbol(kind, track: track)
            Self.symbol(name, tint: active ? .systemOrange : .secondaryLabelColor)?
                .draw(in: frame.insetBy(dx: 3, dy: 3))
        }
    }

    private func buttons(for row: TimelineLayout.Row) -> [(Switch, NSRect)] {
        let size = Self.buttonSize
        let y = row.y + (row.height - size) / 2
        let lock = NSRect(x: bounds.width - 6 - size, y: y, width: size, height: size)
        let other = NSRect(x: lock.minX - size, y: y, width: size, height: size)
        return [(row.track.isVisual ? .hidden : .muted, other), (.locked, lock)]
    }

    override func mouseDown(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        point.y += scrollOffset
        guard let row = layout.rows.first(where: { point.y >= $0.y && point.y < $0.maxY }) else { return }
        if let hit = buttons(for: row).first(where: { $0.1.contains(point) }) {
            onToggle?(row.track.id, hit.0)
        } else {
            onSelect?(row.track.id)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var point = convert(event.locationInWindow, from: nil)
        point.y += scrollOffset
        guard let row = layout.rows.first(where: { point.y >= $0.y && point.y < $0.maxY }) else { return nil }
        onSelect?(row.track.id)
        return onMenu?(row.track.id)
    }

    override func resetCursorRects() {
        for row in layout.rows {
            for (_, frame) in buttons(for: row) {
                // Buttons scrolled out of view intersect to a null (infinite) rect, which AppKit rejects.
                let visible = frame.offsetBy(dx: 0, dy: -scrollOffset).intersection(bounds)
                if !visible.isNull, !visible.isEmpty { addCursorRect(visible, cursor: .pointingHand) }
            }
        }
    }

    // MARK: Symbols

    private static func icon(for track: Track) -> String {
        switch track.role {
        case TrackRole.main: "film"
        case TrackRole.overlay: "photo.on.rectangle"
        case TrackRole.dialogue: "waveform"
        case TrackRole.voiceover: "mic"
        case TrackRole.music: "music.note"
        case TrackRole.sfx: "speaker.wave.2"
        default:
            track.isAdjustment ? "camera.filters"
                : track.kind == "text" ? "textformat" : track.kind == "audio" ? "waveform" : "rectangle.stack"
        }
    }

    private static func switchSymbol(_ kind: Switch, track: Track) -> (String, Bool) {
        switch kind {
        case .hidden: (track.isHidden ? "eye.slash" : "eye", track.isHidden)
        case .muted: (track.isMuted ? "speaker.slash" : "speaker.wave.2", track.isMuted)
        case .locked: (track.isLocked ? "lock.fill" : "lock.open", track.isLocked)
        }
    }

    static func symbol(_ name: String, tint: NSColor) -> NSImage? {
        let key = name + tint.description
        if let cached = symbols[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(.init(paletteColors: [tint]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        symbols[key] = image
        return image
    }
}

/// The current time drawn in red above the layer names.
final class TimelineTimeLabel: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.systemRed,
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill()
        dirtyRect.intersection(bounds).fill()
        (text as NSString).draw(at: NSPoint(x: 8, y: 5), withAttributes: Self.attributes)
    }
}
