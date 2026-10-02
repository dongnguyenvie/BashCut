import AppKit

extension TimelineCanvas {
    /// Labels at a round interval at least ~60 points apart; frame ticks once frames are wide enough to see.
    func drawRuler(_ dirtyRect: CGRect) {
        let ruler = CGRect(x: 0, y: 0, width: bounds.width, height: TimelineLayout.rulerHeight)
        guard ruler.intersects(dirtyRect) else { return }
        NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
        ruler.intersection(dirtyRect).fill()
        let pointsPerSecond = document.ui.timelineScale
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let step = steps.first { $0 * pointsPerSecond >= 60 } ?? 3600
        let seconds = Double(project.duration) / project.fps.value + step * 2
        NSColor.darkGray.setStroke()
        if scale >= 6 {
            let first = max(0, Int((dirtyRect.minX - TimelineLayout.leading) / scale))
            let last = min(Int(seconds * project.fps.value), Int((dirtyRect.maxX - TimelineLayout.leading) / scale) + 1)
            if first <= last {
                let ticks = NSBezierPath()
                for frame in first...last {
                    ticks.move(to: CGPoint(x: layout.x(frame), y: 17))
                    ticks.line(to: CGPoint(x: layout.x(frame), y: 21))
                }
                ticks.stroke()
            }
        }
        let lines = NSBezierPath()
        for second in stride(from: 0.0, through: seconds, by: step) {
            let x = TimelineLayout.leading + second * pointsPerSecond
            if x < dirtyRect.minX - 60 || x > dirtyRect.maxX { continue }
            let whole = Int(second)
            let label = step >= 60 || whole >= 60 ? String(format: "%d:%02d", whole / 60, whole % 60) : "\(whole)s"
            (label as NSString).draw(at: CGPoint(x: x + 3, y: 4), withAttributes: ClipStyle.rulerText)
            lines.move(to: CGPoint(x: x, y: 0))
            lines.line(to: CGPoint(x: x, y: TimelineLayout.rulerHeight))
        }
        lines.stroke()
    }

    /// Trackpad pinch zooms around the pointer.
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// ⌘ + scroll zooms around the pointer; other scrolling pans (⇧ + wheel pans sideways).
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.scrollWheel(with: event) }
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
        zoom(by: Foundation.exp(delta), at: convert(event.locationInWindow, from: nil))
    }

    private func zoom(by factor: Double, at point: CGPoint) {
        document.ui.magnifyTimeline(by: factor, at: layout.frame(at: point.x), viewOffset: point.x - visibleRect.minX)
    }
}
