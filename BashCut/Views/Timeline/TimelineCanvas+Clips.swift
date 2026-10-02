import AppKit
import BashCutEngine
import BashCutProject

/// Colors, fonts and icons for clips, one look per kind of layer.
@MainActor enum ClipStyle {
    static func color(track: Track, item: Item) -> NSColor {
        switch track.role {
        case TrackRole.main: return mainColor(item)
        case TrackRole.overlay: return NSColor(srgbRed: 0.30, green: 0.36, blue: 0.80, alpha: 1)
        case TrackRole.dialogue: return NSColor(srgbRed: 0.20, green: 0.58, blue: 0.32, alpha: 1)
        case TrackRole.voiceover: return NSColor(srgbRed: 0.10, green: 0.50, blue: 0.75, alpha: 1)
        case TrackRole.music: return NSColor(srgbRed: 0.55, green: 0.30, blue: 0.70, alpha: 1)
        case TrackRole.sfx: return NSColor(srgbRed: 0.75, green: 0.30, blue: 0.50, alpha: 1)
        default:
            if track.kind == "text" { return NSColor(srgbRed: 0.85, green: 0.50, blue: 0.15, alpha: 1) }
            return track.kind == "audio" ? NSColor(srgbRed: 0.20, green: 0.58, blue: 0.32, alpha: 1) : .systemTeal
        }
    }

    private static func mainColor(_ item: Item) -> NSColor {
        switch item["tag"]?.object["role"]?.string {
        case "speech": NSColor(srgbRed: 0.18, green: 0.45, blue: 0.85, alpha: 1)
        case "underVO": NSColor(srgbRed: 0.45, green: 0.32, blue: 0.78, alpha: 1)
        default: NSColor(srgbRed: 0.10, green: 0.55, blue: 0.58, alpha: 1)
        }
    }

    static let titleText: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white,
    ]
    static let durationText: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.75),
    ]
    static let sectionText: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white,
    ]
    static let rulerText: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.gray,
    ]

    private static var icons: [String: NSImage] = [:]

    /// A white SF Symbol at clip-title size, cached.
    static func icon(_ name: String, tint: NSColor = .white) -> NSImage? {
        let key = name + tint.description
        if let icon = icons[key] { return icon }
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(.init(paletteColors: [tint]))
        let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        icons[key] = icon
        return icon
    }
}

extension NSImage {
    /// Draws right side up in flipped views.
    func drawFlipped(in rect: NSRect, fraction: Double = 1) {
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction, respectFlipped: true, hints: nil)
    }
}

extension TimelineCanvas {
    func drawClip(_ item: Item, in rect: CGRect, row: TimelineLayout.Row, dirtyRect: CGRect, root: URL?) {
        let track = row.track
        let base = ClipStyle.color(track: track, item: item)
        let fade = track.isHidden ? 0.35 : track.isMuted ? 0.5 : 1
        let hovered = item.id == hoveredItemID
        let selected = item.id == selectedID
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        base.withAlphaComponent(0.75 * fade).setFill()
        rect.fill()
        let filmstrip = track.kind == "video" && row.height >= TimelineLayout.mainRowHeight
        if filmstrip { drawFilmstrip(item, in: rect, dirtyRect: dirtyRect, root: root, fade: fade) }
        if track.kind == "audio" {
            drawWaveform(item: item, in: rect, dirtyRect: dirtyRect)
        } else if track.role == TrackRole.main, item["linkedAudio"] == nil {
            drawWaveform(item: item, in: CGRect(x: rect.minX, y: rect.maxY - 12, width: rect.width, height: 12),
                         dirtyRect: dirtyRect)
        }
        if filmstrip {
            NSColor.black.withAlphaComponent(0.45).setFill()
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 15).fill()
        }
        if track.isLocked { drawLockStripes(rect) }
        if hovered && !selected {
            NSColor.white.withAlphaComponent(0.08).setFill()
            rect.fill()
        }
        drawTitle(item, track: track, in: rect, compact: !filmstrip)
        NSGraphicsContext.restoreGraphicsState()

        if selected {
            NSColor.white.setStroke()
            path.lineWidth = 2
        } else {
            (hovered ? NSColor.white.withAlphaComponent(0.55) : base.blended(withFraction: 0.35, of: .black) ?? base)
                .setStroke()
            path.lineWidth = 1
        }
        path.stroke()
        drawVoiceoverWarning(track: track, item: item, path: path, rect: rect)
        if hovered || selected, !track.isLocked, rect.width > 16 { drawTrimHandles(rect) }
    }

    private func drawTitle(_ item: Item, track: Track, in rect: CGRect, compact: Bool) {
        var x = rect.minX + 5
        let y = compact ? rect.midY - 6 : rect.minY + 2
        var icons: [String] = []
        if document.agentChangedIDs.contains(item.id) { icons.append("sparkle") }
        if item.linkedItemID != nil { icons.append("link") }
        if item.fields["freezeFrame"] != nil { icons.append("snowflake") }
        if item["muted"] == .bool(true) { icons.append("speaker.slash.fill") }
        for name in icons {
            ClipStyle.icon(name)?.drawFlipped(in: CGRect(x: x, y: y + 1, width: 10, height: 10))
            x += 12
        }
        let filename = item.mediaID.flatMap { mediaByID[$0] }.map {
            URL(fileURLWithPath: $0.path).lastPathComponent
        } ?? item.id
        let duration = Timecode.duration(item.duration, fps: project.fps)
        let durationWidth = (duration as NSString).size(withAttributes: ClipStyle.durationText).width
        let showsDuration = rect.width > durationWidth + 60
        let titleWidth = rect.maxX - x - 4 - (showsDuration && compact ? durationWidth + 6 : 0)
        if titleWidth > 8 {
            ((item.text.isEmpty ? filename : item.text) as NSString).draw(
                with: CGRect(x: x, y: y, width: titleWidth, height: 13),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: ClipStyle.titleText)
        }
        guard showsDuration else { return }
        let durationY = compact ? rect.midY - 6 : rect.maxY - 13
        (duration as NSString).draw(
            at: CGPoint(x: rect.maxX - durationWidth - 5, y: durationY), withAttributes: ClipStyle.durationText)
    }

    private func drawLockStripes(_ rect: CGRect) {
        NSColor.black.withAlphaComponent(0.25).setStroke()
        let stripes = NSBezierPath()
        for x in stride(from: rect.minX - rect.height, through: rect.maxX, by: 6) {
            stripes.move(to: CGPoint(x: x, y: rect.maxY))
            stripes.line(to: CGPoint(x: x + rect.height, y: rect.minY))
        }
        stripes.stroke()
    }

    /// CapCut-style brackets on both ends of the clip under the pointer or selected.
    private func drawTrimHandles(_ rect: CGRect) {
        for x in [rect.minX, rect.maxX - 6] {
            let handle = CGRect(x: x, y: rect.minY, width: 6, height: rect.height)
            NSColor.white.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
            NSColor.black.withAlphaComponent(0.45).setFill()
            CGRect(x: handle.midX - 0.5, y: handle.midY - 5, width: 1, height: 10).fill()
        }
    }

    func drawWaveform(item: Item, in rect: CGRect, dirtyRect: CGRect) {
        guard let media = item.mediaID.flatMap({ mediaByID[$0] }),
            let waveform = waveforms[media.id], waveform.hasAudio
        else { return }
        let visible = rect.intersection(dirtyRect).intersection(visibleRect)
        guard !visible.isNull else { return }
        let path = NSBezierPath()
        let sourceStart = Double(item.sourceIn) / media.fps.value
        let secondsPerPoint = item.speed / (project.fps.value * scale)
        let amplitude = rect.height / 2 - 2
        for x in stride(from: visible.minX, through: visible.maxX, by: 2) {
            let start = sourceStart + (x - rect.minX) * secondsPerPoint
            let peak = waveform.peak(from: start, to: start + 2 * secondsPerPoint)
            let height = max(0.5, Double(peak) * amplitude)
            path.move(to: CGPoint(x: x, y: rect.midY - height))
            path.line(to: CGPoint(x: x, y: rect.midY + height))
        }
        NSColor.white.withAlphaComponent(item["muted"] == .bool(true) ? 0.12 : 0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func drawVoiceoverWarning(track: Track, item: Item, path: NSBezierPath, rect: CGRect) {
        guard track.role == TrackRole.voiceover, voiceoverWarningIDs.contains(item.id) else { return }
        NSColor.systemRed.setStroke()
        path.lineWidth = 2
        path.stroke()
        let badge = CGRect(x: max(rect.minX, rect.maxX - 17), y: rect.minY + 2, width: 15, height: 15)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        ("!" as NSString).draw(
            in: badge,
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white, .paragraphStyle: style])
    }

    func updateReviewWarnings(for project: Project) {
        guard project.revision != reviewRevision else { return }
        reviewRevision = project.revision
        voiceoverWarningIDs = Set(
            TimelineReview.run(project).compactMap { issue in
                issue.id.hasPrefix("overlap-") ? String(issue.id.dropFirst("overlap-".count)) : nil
            })
    }

    /// Thumbnails along a video clip, one per tile, from the preview proxy when there is one.
    private func drawFilmstrip(_ item: Item, in rect: CGRect, dirtyRect: CGRect, root: URL?, fade: Double) {
        guard let root, let media = item.mediaID.flatMap({ mediaByID[$0] }),
            let url = filmstripURL(media, root: root)
        else { return }
        let tileWidth = max(12, rect.height * Double(project.width) / Double(max(1, project.height)))
        let visible = rect.intersection(dirtyRect).intersection(visibleRect)
        guard !visible.isNull else { return }
        let secondsPerPoint = item.speed / (project.fps.value * scale)
        let sourceStart = Double(item.sourceIn) / media.fps.value
        let freeze = item["freezeFrame"]?.int.map { Double($0) / media.fps.value }
        let quantum = FilmstripCache.quantum(for: tileWidth * secondsPerPoint, fps: media.fps.value)
        let first = Int(((visible.minX - rect.minX) / tileWidth).rounded(.down))
        let last = Int(((visible.maxX - rect.minX) / tileWidth).rounded(.up))
        guard first <= last else { return }
        for index in first...last {
            let tile = CGRect(x: rect.minX + Double(index) * tileWidth, y: rect.minY, width: tileWidth, height: rect.height)
            let seconds = freeze ?? (sourceStart + (tile.minX - rect.minX) * secondsPerPoint)
            if let image = filmstrips.image(url: url, seconds: seconds, quantum: quantum) {
                image.drawFlipped(in: tile, fraction: 0.9 * fade)
            }
        }
    }
}
