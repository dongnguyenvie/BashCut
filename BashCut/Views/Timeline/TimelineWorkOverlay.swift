import AppKit
import BashCutProject

/// The agent's work over the timeline (#534): placeholders for blocks being made (dashed, with a moving shimmer and
/// their state), the ranges an agent holds (its attached scope), and a brief flash on items it just added or changed.
/// A layer-backed view over the canvas, so the clips never redraw for it; it takes clicks only on a placeholder.
final class TimelineWorkOverlay: NSView {
    struct Box: Equatable {
        let id: String
        let rect: CGRect
        let title: String
        let failed: Bool
        let active: Bool
    }

    /// The menu for a clicked placeholder (Retry, Remove, Cancel).
    var menuFor: ((String) -> NSMenu?)?
    private(set) var boxes: [Box] = []
    private var held: [CGRect] = []
    private var flashes: [CGRect] = []
    private var flashStart: Date?
    private var phase = 0.0
    private var timer: Timer?
    static let flashSeconds = 1.2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func update(boxes: [Box], held: [CGRect]) {
        guard boxes != self.boxes || held != self.held else { return }
        self.boxes = boxes
        self.held = held
        needsDisplay = true
        animate()
    }

    func flash(_ rects: [CGRect]) {
        guard !rects.isEmpty else { return }
        flashes = rects
        flashStart = Date()
        needsDisplay = true
        animate()
    }

    /// One timer drives the shimmer and the flash while either shows; it stops when nothing moves.
    private func animate() {
        let moving = boxes.contains(where: \.active) || flashStart != nil
        if !moving {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        phase = (phase + 0.04).truncatingRemainder(dividingBy: 1.4)
        if let start = flashStart, Date().timeIntervalSince(start) > Self.flashSeconds {
            flashStart = nil
            flashes = []
            needsDisplay = true
        }
        for box in boxes where box.active { setNeedsDisplay(box.rect.insetBy(dx: -2, dy: -2)) }
        for rect in flashes { setNeedsDisplay(rect.insetBy(dx: -3, dy: -3)) }
        animate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return boxes.contains { $0.rect.contains(local) } ? self : nil
    }

    override func mouseDown(with event: NSEvent) { showMenu(event) }
    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    private func showMenu(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let box = boxes.last(where: { $0.rect.contains(point) }), let menu = menuFor?(box.id) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        for rect in held where rect.intersects(dirtyRect) { drawHeld(rect) }
        for box in boxes where box.rect.intersects(dirtyRect) { drawBox(box) }
        if let start = flashStart {
            let alpha = max(0, 1 - Date().timeIntervalSince(start) / Self.flashSeconds)
            for rect in flashes where rect.intersects(dirtyRect) {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 5, yRadius: 5)
                NSColor.systemCyan.withAlphaComponent(0.35 * alpha).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(0.9 * alpha).setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }
    }

    private func drawHeld(_ rect: CGRect) {
        NSColor.systemOrange.withAlphaComponent(0.08).setFill()
        rect.fill()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.setLineDash([3, 3], count: 2, phase: 0)
        NSColor.systemOrange.withAlphaComponent(0.6).setStroke()
        path.stroke()
        (String(localized: "Agent's scope") as NSString).draw(
            at: CGPoint(x: rect.minX + 4, y: rect.maxY - 12),
            withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                             .foregroundColor: NSColor.systemOrange.withAlphaComponent(0.9)])
    }

    private func drawBox(_ box: Box) {
        let color = box.failed ? NSColor.systemOrange : NSColor.systemCyan
        let rect = box.rect.insetBy(dx: 0.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor(calibratedWhite: 0.16, alpha: 0.92).setFill()
        path.fill()
        if box.active, let context = NSGraphicsContext.current {
            // A soft band that sweeps across while the job runs.
            context.saveGraphicsState()
            path.addClip()
            let x = rect.minX + (phase - 0.2) * max(rect.width, 120)
            NSGradient(colors: [color.withAlphaComponent(0), color.withAlphaComponent(0.22), color.withAlphaComponent(0)])?
                .draw(in: CGRect(x: x, y: rect.minY, width: 80, height: rect.height), angle: 0)
            context.restoreGraphicsState()
        }
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.lineWidth = 1.2
        color.withAlphaComponent(0.9).setStroke()
        path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color.withAlphaComponent(0.95),
        ]
        (box.title as NSString).draw(
            in: CGRect(x: rect.minX + 5, y: rect.minY + 3, width: max(0, rect.width - 8), height: 12),
            withAttributes: attributes)
    }
}

extension TimelineWorkOverlay {
    /// The placeholders on the timeline and the held ranges, in canvas coordinates.
    @MainActor static func content(_ document: ProjectDocument, layout: TimelineLayout) -> (boxes: [Box], held: [CGRect]) {
        let boxes = document.activity.placeholders.items.compactMap { placeholder -> Box? in
            guard let trackID = placeholder.target.trackID, let frames = placeholder.target.frames,
                let row = layout.rows.first(where: { $0.track.id == trackID })
            else { return nil }
            let width = max(36, Double(frames.count) * layout.scale)
            let rect = CGRect(x: layout.x(frames.lowerBound), y: row.y, width: width, height: row.height)
            let title = placeholder.target.label.isEmpty ? placeholder.title : placeholder.title + " — " + placeholder.target.label
            return Box(id: placeholder.id, rect: rect, title: title, failed: placeholder.failed, active: !placeholder.failed)
        }
        return (boxes, heldRects(document, layout: layout))
    }

    /// The scope agents hold while they work: each attached item's range on its layer.
    @MainActor private static func heldRects(_ document: ProjectDocument, layout: TimelineLayout) -> [CGRect] {
        switch document.activity.status {
        case .working, .waiting: break
        default: return []
        }
        let scopes = document.agents.sessions.flatMap(\.scope) + document.chatAgents.all.flatMap(\.scope)
        return scopes.compactMap { scope in
            let row = layout.rows.first { $0.track.id == scope.track }
            let item = row?.track.items.first { $0.id == scope.id }
            guard let row else { return nil }
            let start = item?.at ?? scope.start, end = item?.end ?? scope.end
            return CGRect(x: layout.x(start), y: row.y - 2, width: max(2, Double(end - start) * layout.scale), height: row.height + 4)
        }
    }
}

extension TimelineWorkOverlay {
    /// A placeholder's menu: its state or error, then Retry and Remove when it failed, Cancel while it runs.
    @MainActor static func menu(_ document: ProjectDocument, id: String) -> NSMenu? {
        guard let placeholder = document.activity.placeholders.items.first(where: { $0.id == id }) else { return nil }
        let menu = NSMenu()
        let header = NSMenuItem(title: placeholder.title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let error = placeholder.error, placeholder.failed {
            let line = NSMenuItem(title: String(error.prefix(120)), action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        let placeholders = document.activity.placeholders
        if placeholder.failed {
            if placeholder.canRetry { menu.addItem(ClosureMenuItem(String(localized: "Retry")) { placeholders.retry(id) }) }
            menu.addItem(ClosureMenuItem(String(localized: "Remove")) { placeholders.remove(id) })
        } else {
            menu.addItem(ClosureMenuItem(String(localized: "Cancel Job")) { placeholders.remove(id) })
        }
        return menu
    }
}
