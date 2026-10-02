import AppKit

/// Light layer-backed views on top of the timeline canvas. Moving them only changes a frame, so the playhead,
/// drag guides and labels follow the pointer and playback without redrawing clips and waveforms.

/// The red playhead: a line through every layer and a grip on the ruler.
final class PlayheadView: NSView {
    static let width = 13.0
    static let gripHeight = 14.0
    var highlighted = false { didSet { if highlighted != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    // Mouse events go to the canvas, which decides between dragging the playhead and editing clips.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color = highlighted ? NSColor.systemRed.blended(withFraction: 0.25, of: .white) ?? .systemRed : .systemRed
        color.setFill()
        let mid = bounds.midX
        NSRect(x: mid - (highlighted ? 1 : 0.75), y: Self.gripHeight - 2, width: highlighted ? 2 : 1.5,
               height: bounds.height).fill()
        let grip = NSBezierPath()
        grip.move(to: NSPoint(x: mid - 6, y: 1))
        grip.line(to: NSPoint(x: mid + 6, y: 1))
        grip.line(to: NSPoint(x: mid + 6, y: Self.gripHeight - 6))
        grip.line(to: NSPoint(x: mid, y: Self.gripHeight))
        grip.line(to: NSPoint(x: mid - 6, y: Self.gripHeight - 6))
        grip.close()
        grip.fill()
    }

    /// Centers the view on `x` across the full height of the canvas.
    func place(atX x: Double, height: Double) {
        let frame = NSRect(x: x - Self.width / 2, y: 0, width: Self.width, height: height)
        guard frame != self.frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        CATransaction.commit()
    }
}

/// A thin vertical line: the drop target of a drag (cyan) or the point a drag snapped to (yellow).
final class GuideLineView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(atX x: Double?, height: Double, width: Double = 1.5) {
        guard let x else {
            isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = NSRect(x: x - width / 2, y: 0, width: width, height: height)
        isHidden = false
        CATransaction.commit()
    }
}

/// A small rounded label next to the pointer: timecodes while scrubbing, new positions and durations while
/// dragging or trimming.
final class TimelineBadgeView: NSView {
    private var text = ""
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white,
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        (text as NSString).draw(at: NSPoint(x: 6, y: 3), withAttributes: Self.attributes)
    }

    /// Shows `text` with its left edge near `x` at `y`, kept inside `bounds` of the canvas' visible area.
    func show(_ text: String?, nearX x: Double, y: Double, within visible: NSRect) {
        guard let text else {
            isHidden = true
            return
        }
        let size = (text as NSString).size(withAttributes: Self.attributes)
        let width = ceil(size.width) + 12
        let originX = min(max(visible.minX + 2, x + 8), visible.maxX - width - 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = NSRect(x: originX, y: y, width: width, height: 17)
        CATransaction.commit()
        if text != self.text {
            self.text = text
            needsDisplay = true
        }
        isHidden = false
    }
}

/// A see-through copy of the clip being dragged, following the pointer onto the layer it would land on.
/// The picture is captured once when the drag starts; moving it only changes the frame.
final class ClipGhostView: NSView {
    private var image: NSImage?
    private var outlineOnly = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Starts showing `image` (a capture of the clip) or, for trims, just an outline.
    func begin(image: NSImage?, outlineOnly: Bool) {
        self.image = image
        self.outlineOnly = outlineOnly
        needsDisplay = true
    }

    func show(_ rect: NSRect?) {
        guard let rect else {
            isHidden = true
            image = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = rect
        CATransaction.commit()
        isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        if !outlineOnly, let image {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }
}
