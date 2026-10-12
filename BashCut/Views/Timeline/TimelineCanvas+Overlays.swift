import AppKit
import BashCutPlugin

/// Plugin overlays on the timeline (#407): ranges tinted over the layers (one layer with `track`) with a bar on the
/// ruler, and markers as a line with a flag. Drawn with the clips, only when the overlays or the content change, so
/// playback and scrolling cost what they cost without them; a redraw looks up only the overlays in its frames.
extension TimelineCanvas {
    func drawPluginOverlays(_ dirtyRect: CGRect) {
        guard !overlays.timeline.isEmpty else { return }
        let first = layout.frame(at: dirtyRect.minX - 1)
        let last = layout.frame(at: dirtyRect.maxX + 1) + 1
        guard first < last else { return }
        let top = TimelineLayout.sectionBand.upperBound
        // Labels go on the first line whose last label ends before them, so a marker and a range that start
        // together (or close) do not print over each other.
        var labelLines: [CGFloat] = []
        for entry in overlays.timeline(in: first..<last) {
            let overlay = entry.overlay
            guard let frames = overlay.frames else { continue }
            let color = Self.overlayColor(overlay.color)
            var band = CGRect(x: layout.x(frames.lowerBound), y: top, width: 0, height: max(0, bounds.height - top))
            if let track = overlay.track, let row = layout.rows.first(where: { $0.track.id == track }) {
                band.origin.y = row.y
                band.size.height = row.height
            }
            switch overlay.kind {
            case .range:
                band.size.width = max(1, Double(frames.count) * scale)
                color.withAlphaComponent(0.13).setFill()
                band.fill()
                color.withAlphaComponent(0.85).setFill()
                CGRect(x: band.minX, y: TimelineLayout.rulerHeight - 3, width: band.width, height: 3).fill()
            case .marker:
                color.withAlphaComponent(0.9).setFill()
                CGRect(x: band.minX - 0.75, y: band.minY, width: 1.5, height: band.height).fill()
                let flag = NSBezierPath()
                flag.move(to: CGPoint(x: band.minX, y: TimelineLayout.rulerHeight - 9))
                flag.line(to: CGPoint(x: band.minX + 7, y: TimelineLayout.rulerHeight - 5))
                flag.line(to: CGPoint(x: band.minX, y: TimelineLayout.rulerHeight - 1))
                flag.close()
                flag.fill()
            case .region:
                continue
            }
            if let label = overlay.label, !label.isEmpty {
                let attributes = Self.overlayText(color)
                let x = band.minX + 4
                let width = min(max(60, band.width - 6), (label as NSString).size(withAttributes: attributes).width + 2)
                let line = labelLines.firstIndex { $0 <= x } ?? labelLines.count
                if line == labelLines.count { labelLines.append(0) }
                labelLines[line] = x + width + 4
                (label as NSString).draw(
                    in: CGRect(x: x, y: band.minY + 2 + CGFloat(line) * 12, width: width, height: 13),
                    withAttributes: attributes)
            }
        }
    }

    static func overlayColor(_ name: String?) -> NSColor {
        switch name {
        case "green": .systemGreen
        case "orange": .systemOrange
        case "red": .systemRed
        case "purple": .systemPurple
        case "secondary": .secondaryLabelColor
        case let hex? where hex.hasPrefix("#"):
            PluginViewColor.components(hex).map {
                NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
            } ?? .systemCyan
        default: .systemCyan
        }
    }

    private static func overlayText(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color.withAlphaComponent(0.95)]
    }
}
