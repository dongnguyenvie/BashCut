import AppKit
import BashCutDocument
import BashCutProject

/// The layer header pinned to the left edge of the timeline while it scrolls sideways: the current time over
/// the ruler, then per layer its short ID (V1, A1), an icon and switches (hide for visual layers, mute for audio
/// layers, lock for all). Compact by default (#531); dragged wider it adds the full names. Clicking a row selects
/// the layer, double-clicking renames it, and dragging the right edge resizes the header.
final class TimelineHeaderView: NSView, NSTextFieldDelegate, NSViewToolTipOwner {
    enum Switch { case hidden, muted, locked }

    var layout = TimelineLayout(project: Project(name: ""), scale: 1) {
        didSet {
            guard !layout.sameRows(as: oldValue) else { return }
            needsDisplay = true
            updateToolTips()
        }
    }
    var selectedTrackID: String? { didSet { if selectedTrackID != oldValue { needsDisplay = true } } }
    /// The playhead time over the ruler. A subview of its own, so playback redraws only this label.
    let time = TimelineTimeLabel(
        frame: NSRect(x: 0, y: 0, width: EditorUIState.compactTimelineLeading - 1, height: TimelineLayout.rulerHeight))
    /// Vertical scroll offset of the timeline; content is drawn shifted up by it (bounds never move, so nothing
    /// is drawn outside the view).
    var scrollOffset = 0.0 {
        didSet {
            guard scrollOffset != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            updateToolTips()
        }
    }
    var onSelect: ((String) -> Void)?
    var onToggle: ((String, Switch) -> Void)?
    var onRename: ((String, String) -> Void)?
    /// The header's new width while its edge is dragged.
    var onResize: ((Double) -> Void)?
    /// The context menu for a layer row (plugin `track.context` actions); the row is selected first.
    var onMenu: ((String) -> NSMenu?)?
    /// Folds or unfolds the empty layers (the row under the last layer).
    var onToggleEmpty: (() -> Void)?
    /// The menu "+ Add track" opens, one entry per kind of layer.
    var onAddMenu: (() -> NSMenu?)?

    private static let chipWidth = 22.0
    /// The grab area at the right edge that resizes the header.
    private static let edgeWidth = 4.0
    private static var symbols: [String: NSImage] = [:]
    private var resizing = false
    private var renameField: NSTextField?
    private var renamingTrackID: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(time)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        time.frame.size.width = max(0, newSize.width - 1)
        guard changed else { return }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        updateToolTips()
    }

    /// Short IDs and switches only; the names need the wide header.
    private var isCompact: Bool {
        bounds.width < (EditorUIState.compactTimelineLeading + EditorUIState.wideTimelineLeading) / 2
    }
    private var buttonSize: Double { isCompact ? 15 : 18 }

    override func draw(_ dirtyRect: NSRect) {
        // Fill only inside our bounds: AppKit may hand this overlay a dirty rect larger than the view, and a
        // copy-mode fill there paints over the sibling SwiftUI views.
        let visible = dirtyRect.intersection(bounds)
        guard !visible.isNull else { return }
        NSColor(calibratedWhite: 0.095, alpha: 1).setFill()
        visible.fill()
        NSColor(calibratedWhite: 1, alpha: resizing ? 0.3 : 0.08).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill(using: .sourceOver)
        NSBezierPath(rect: bounds).setClip()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: -scrollOffset)
        shift.concat()
        let area = visible.offsetBy(dx: 0, dy: scrollOffset)
        (String(localized: "Sections") as NSString).draw(
            with: NSRect(x: 6, y: TimelineLayout.sectionBand.lowerBound + 4, width: bounds.width - 10, height: 14),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
        for row in layout.rows where NSRect(x: 0, y: row.y, width: bounds.width, height: row.height).intersects(area) {
            draw(row)
        }
        drawFooters()
    }

    /// The row that folds the empty layers ("V1, V3, A1 empty"; "Hide empty" once shown) and the "+ Add track" row.
    private func footerRects() -> (empty: NSRect?, add: NSRect) {
        let inset = bounds.width - 1
        return (
            layout.emptyRowY.map { NSRect(x: 0, y: $0, width: inset, height: TimelineLayout.footerRowHeight) },
            NSRect(x: 0, y: layout.addRowY, width: inset, height: TimelineLayout.footerRowHeight))
    }

    /// What the fold row says: the empty layers' IDs in the wide header, their count in the compact one.
    private var emptyTitle: String {
        let labels = layout.emptyLabels
        if layout.emptyExpanded { return String(localized: "Hide empty") }
        return isCompact
            ? String(format: String(localized: "%d empty"), labels.count)
            : String(format: String(localized: "%@ empty"), labels.joined(separator: ", "))
    }

    private func drawFooters() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isCompact ? 9 : 10), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let rects = footerRects()
        if let rect = rects.empty {
            NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 0), xRadius: 4, yRadius: 4).fill()
            Self.symbol(layout.emptyExpanded ? "chevron.down" : "chevron.right", tint: .tertiaryLabelColor)?
                .draw(in: NSRect(x: 8, y: rect.midY - 5, width: 10, height: 10))
            (emptyTitle as NSString).draw(
                with: NSRect(x: 22, y: rect.midY - 7, width: max(0, rect.width - 26), height: 14),
                options: options, attributes: attributes)
        }
        (String(localized: "+ Add track") as NSString).draw(
            with: NSRect(x: 9, y: rects.add.midY - 7, width: max(0, rects.add.width - 12), height: 14),
            options: options, attributes: attributes)
    }

    /// The vertical center of a row's ID, icon and switches; a selected compact row moves them up to make room for
    /// its name.
    private func centerY(_ row: TimelineLayout.Row) -> Double {
        isCompact && row.track.id == selectedTrackID ? row.y + min(row.height / 2, 11) : row.y + row.height / 2
    }

    private func chipRect(_ row: TimelineLayout.Row) -> NSRect {
        NSRect(x: 5, y: centerY(row) - 7, width: Self.chipWidth, height: 14)
    }

    private func draw(_ row: TimelineLayout.Row) {
        let track = row.track
        let selected = track.id == selectedTrackID
        let rect = NSRect(x: 0, y: row.y, width: bounds.width - 1, height: row.height)
        (selected ? NSColor.systemCyan.withAlphaComponent(0.16) : NSColor(calibratedWhite: 0.13, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 0), xRadius: 4, yRadius: 4).fill()
        let dimmed = track.isHidden || track.isMuted
        let center = centerY(row)
        drawChip(layout.labels[track.id] ?? "", in: chipRect(row), main: track.role == TrackRole.main, dimmed: dimmed)
        let iconSize = isCompact ? 12.0 : 14.0
        let iconX = Self.chipWidth + (isCompact ? 8 : 9)
        Self.symbol(Self.icon(for: track), tint: dimmed ? .tertiaryLabelColor : .secondaryLabelColor)?
            .draw(in: NSRect(x: iconX, y: center - iconSize / 2, width: iconSize, height: iconSize))
        let firstButton = buttons(for: row).map(\.1.minX).min() ?? bounds.width
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: isCompact ? 8 : 10, weight: track.role == TrackRole.main ? .semibold : .regular),
            .foregroundColor: dimmed ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        if !isCompact {
            let nameX = iconX + iconSize + 4
            (track.name as NSString).draw(
                with: NSRect(x: nameX, y: center - 7, width: max(0, firstButton - nameX - 2), height: 14),
                options: options, attributes: attributes)
        } else if selected, track.id != renamingTrackID {
            (track.name as NSString).draw(
                with: NSRect(x: 6, y: center + 8, width: bounds.width - 12, height: 11), options: options,
                attributes: attributes)
        }
        for (kind, frame) in buttons(for: row) {
            let (name, active) = Self.switchSymbol(kind, track: track)
            Self.symbol(name, tint: active ? .systemOrange : .secondaryLabelColor)?
                .draw(in: frame.insetBy(dx: isCompact ? 2 : 3, dy: isCompact ? 2 : 3))
        }
    }

    /// The short ID; the main layer's chip is filled so the magnetic layer stands out.
    private func drawChip(_ label: String, in rect: NSRect, main: Bool, dimmed: Bool) {
        let chip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        let text: NSColor
        if main {
            NSColor.systemCyan.withAlphaComponent(dimmed ? 0.35 : 0.8).setFill()
            chip.fill()
            text = .black
        } else {
            NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
            chip.lineWidth = 1
            chip.stroke()
            text = dimmed ? .tertiaryLabelColor : .secondaryLabelColor
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (label as NSString).draw(
            with: rect.offsetBy(dx: 0, dy: 1.5),
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold), .foregroundColor: text,
                .paragraphStyle: style,
            ])
    }

    private func buttons(for row: TimelineLayout.Row) -> [(Switch, NSRect)] {
        let size = buttonSize
        let y = centerY(row) - size / 2
        let lock = NSRect(x: bounds.width - 5 - size, y: y, width: size, height: size)
        let other = NSRect(x: lock.minX - size, y: y, width: size, height: size)
        return [(row.track.isVisual ? .hidden : .muted, other), (.locked, lock)]
    }

    private func row(at point: NSPoint) -> TimelineLayout.Row? {
        layout.rows.first { point.y >= $0.y && point.y < $0.maxY }
    }

    private func onEdge(_ point: NSPoint) -> Bool { point.x >= bounds.width - Self.edgeWidth }

    override func mouseDown(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        if onEdge(point) {
            resizing = true
            needsDisplay = true
            return
        }
        point.y += scrollOffset
        let footers = footerRects()
        if footers.empty?.contains(point) == true {
            onToggleEmpty?()
            return
        }
        if footers.add.contains(point) {
            if let menu = onAddMenu?() { menu.popUp(positioning: nil, at: NSPoint(x: 6, y: footers.add.maxY - scrollOffset), in: self) }
            return
        }
        guard let row = row(at: point) else { return }
        if let hit = buttons(for: row).first(where: { $0.1.contains(point) }) {
            onToggle?(row.track.id, hit.0)
        } else if event.clickCount == 2 {
            beginRename(row)
        } else {
            onSelect?(row.track.id)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizing else { return }
        onResize?(convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        guard resizing else { return }
        resizing = false
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var point = convert(event.locationInWindow, from: nil)
        point.y += scrollOffset
        guard let row = row(at: point) else { return nil }
        onSelect?(row.track.id)
        return onMenu?(row.track.id)
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: bounds.width - Self.edgeWidth, y: 0, width: Self.edgeWidth, height: bounds.height),
                      cursor: .resizeLeftRight)
        for footer in [footerRects().empty, footerRects().add].compactMap({ $0 }) {
            let visible = footer.offsetBy(dx: 0, dy: -scrollOffset).intersection(bounds)
            if !visible.isNull, !visible.isEmpty { addCursorRect(visible, cursor: .pointingHand) }
        }
        for row in layout.rows {
            for (_, frame) in buttons(for: row) {
                // Buttons scrolled out of view intersect to a null (infinite) rect, which AppKit rejects.
                let visible = frame.offsetBy(dx: 0, dy: -scrollOffset).intersection(bounds)
                if !visible.isNull, !visible.isEmpty { addCursorRect(visible, cursor: .pointingHand) }
            }
        }
    }

    // MARK: Rename

    /// Edits the layer name in place over its row; Return or leaving the field renames, Escape cancels.
    private func beginRename(_ row: TimelineLayout.Row) {
        endRename(commit: false)
        onSelect?(row.track.id)
        let height = 18.0
        let field = NSTextField(
            frame: NSRect(
                x: 4, y: row.y - scrollOffset + (row.height - height) / 2, width: max(60, bounds.width - 8),
                height: height))
        field.stringValue = row.track.name
        field.font = .systemFont(ofSize: 10)
        field.focusRingType = .none
        field.delegate = self
        renamingTrackID = row.track.id
        renameField = field
        addSubview(field)
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func endRename(commit: Bool) {
        guard let field = renameField, let id = renamingTrackID else { return }
        renameField = nil
        renamingTrackID = nil
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        needsDisplay = true
        if commit, !name.isEmpty, name != layout.row(for: id)?.track.name { onRename?(id, name) }
    }

    func controlTextDidEndEditing(_ notification: Notification) { endRename(commit: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(cancelOperation(_:)) else { return false }
        endRename(commit: false)
        return true
    }

    // MARK: Tooltips

    /// One tooltip area per visible ID and switch; `view(_:stringForToolTip:point:userData:)` names what is there.
    private func updateToolTips() {
        removeAllToolTips()
        for footer in [footerRects().empty, footerRects().add].compactMap({ $0 }) {
            let visible = footer.offsetBy(dx: 0, dy: -scrollOffset).intersection(bounds)
            if !visible.isNull, !visible.isEmpty { addToolTip(visible, owner: self, userData: nil) }
        }
        for row in layout.rows {
            for rect in [chipRect(row)] + buttons(for: row).map(\.1) {
                let visible = rect.offsetBy(dx: 0, dy: -scrollOffset).intersection(bounds)
                if !visible.isNull, !visible.isEmpty { addToolTip(visible, owner: self, userData: nil) }
            }
        }
    }

    func view(
        _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?
    ) -> String {
        let point = NSPoint(x: point.x, y: point.y + scrollOffset)
        let footers = footerRects()
        if footers.empty?.contains(point) == true {
            return layout.emptyExpanded
                ? String(localized: "Fold the empty layers into one row")
                : String(format: String(localized: "Empty layers: %@. Click to show them."), layout.emptyLabels.joined(separator: ", "))
        }
        if footers.add.contains(point) { return String(localized: "Add a layer") }
        guard let row = row(at: point) else { return "" }
        let track = row.track
        if let hit = buttons(for: row).first(where: { $0.1.contains(point) }) {
            return switch hit.0 {
            case .hidden: String(localized: track.isHidden ? "Show layer" : "Hide layer")
            case .muted: String(localized: track.isMuted ? "Unmute layer" : "Mute layer")
            case .locked: String(localized: track.isLocked ? "Unlock layer" : "Lock layer")
            }
        }
        let title = layout.labels[track.id].map { "\($0) · \(track.name)" } ?? track.name
        return title + "\n" + String(localized: "Double-click to rename")
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
        (text as NSString).draw(at: NSPoint(x: 6, y: 5), withAttributes: Self.attributes)
    }
}
