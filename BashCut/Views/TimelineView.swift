import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

struct TimelineView: NSViewRepresentable {
    let document: ProjectDocument
    func makeNSView(context: Context) -> NSScrollView {
        let view = NSScrollView()
        view.hasHorizontalScroller = true
        view.hasVerticalScroller = true
        view.documentView = TimelineCanvas(document: document)
        return view
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let canvas = view.documentView as? TimelineCanvas else { return }
        canvas.project = document.project
        canvas.updateReviewWarnings(for: document.project)
        canvas.waveforms = document.waveforms.values
        canvas.selectedID = document.selectedID
        canvas.playhead = document.playhead
        canvas.scale = document.ui.timelineScale / document.project.fps.value
        canvas.setFrameSize(
            CGSize(
                width: max(
                    view.contentSize.width, 105 + Double(document.project.duration) * canvas.scale + 100),
                height: max(view.contentSize.height, Double(canvas.orderedTracks.count) * 35 + 58)))
        canvas.needsDisplay = true
        if let reveal = document.ui.timelineReveal, reveal != canvas.lastReveal {
            canvas.lastReveal = reveal
            let x = 105 + Double(reveal.frame) * canvas.scale
            canvas.scrollToVisible(CGRect(x: max(0, x - 120), y: view.documentVisibleRect.minY, width: 240, height: 1))
        }
    }
}

@MainActor final class TimelineCanvas: NSView {
    var waveforms: [String: AudioWaveform] = [:]
    var project: Project
    var selectedID: String?
    var playhead = 0
    var scale = 1.5
    var lastReveal: TimelineReveal?
    fileprivate var voiceoverWarningIDs: Set<String> = []
    fileprivate var reviewRevision = -1
    private let document: ProjectDocument
    private var dragState: (item: Item, track: Track, origin: CGPoint, edge: BashCutProject.Edge?)?
    private var dragFrame: Int?
    private var rolling = false
    private var slipping = false
    private var sectionDrag: TimelineMarker?
    private var slipSourceIn: Int?
    private var dragRevision = 0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var orderedTracks: [Track] {
        let visual = project.tracks.filter { $0.kind != "audio" }.reversed()
        let audio = project.tracks.filter { $0.kind == "audio" }
        return Array(visual) + audio
    }
    init(document: ProjectDocument) {
        self.document = document
        project = document.project
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
        dirtyRect.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.gray,
        ]
        let seconds = max(1, Int(Double(project.duration) / project.fps.value) + 2)
        let step = max(1, Int(50 / document.ui.timelineScale))
        for second in stride(from: 0, through: seconds, by: step) {
            let x = 105 + Double(second) * document.ui.timelineScale
            if x < dirtyRect.minX || x > dirtyRect.maxX { continue }
            ("\(second)s" as NSString).draw(at: CGPoint(x: x + 3, y: 5), withAttributes: attrs)
            NSColor.darkGray.setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: 0))
            line.line(to: CGPoint(x: x, y: 20))
            line.stroke()
        }
        drawSectionBand(dirtyRect)
        drawBeatGrid(dirtyRect)
        let warningIDs = voiceoverWarningIDs
        for (row, track) in orderedTracks.enumerated() {
            let y = Double(row) * 35 + 52
            let rowRect = CGRect(x: 0, y: y, width: bounds.width, height: 29)
            guard rowRect.intersects(dirtyRect) else { continue }
            if track.id == document.selectedTrackID {
                NSColor.systemCyan.withAlphaComponent(0.08).setFill()
                rowRect.fill()
            }
            (track.name as NSString).draw(
                in: CGRect(x: 8, y: y + 5, width: 92, height: 18), withAttributes: attrs)
            for item in track.items {
                let rect = CGRect(
                    x: 105 + Double(item.at) * scale, y: y, width: max(3, Double(item.duration) * scale - 2),
                    height: 29)
                guard rect.intersects(dirtyRect) else { continue }
                fillColor(track: track, item: item).setFill()
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                path.fill()
                if track.kind == "audio" || track.role == "main" {
                    drawWaveform(item: item, rect: rect, dirtyRect: dirtyRect)
                }
                if item.id == selectedID {
                    NSColor.white.setStroke()
                    path.lineWidth = 2
                    path.stroke()
                }
                drawVoiceoverWarning(
                    track: track, item: item, path: path, rect: rect, warningIDs: warningIDs)
                let filename =
                    project.media.first { $0.id == item.mediaID }.map {
                        URL(fileURLWithPath: $0.path).lastPathComponent
                    } ?? item.id
                let title =
                    (document.agentChangedIDs.contains(item.id) ? "◆ " : "")
                    + (item.linkedItemID == nil ? "" : "🔗 ")
                    + (item.fields["freezeFrame"] == nil ? "" : "❄️ ")
                    + (item.text.isEmpty ? filename : item.text)
                (title as NSString).draw(
                    in: rect.insetBy(dx: 5, dy: 6),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
            }
        }
        drawLine(frame: playhead, color: .systemRed)
        if let dragFrame { drawLine(frame: dragFrame, color: .systemCyan) }
    }
    private func drawSectionBand(_ dirtyRect: CGRect) {
        let sections = project.sectionMarkers
        let band = CGRect(x: 105, y: 24, width: max(0, bounds.width - 105), height: 22)
        guard band.intersects(dirtyRect) else { return }
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        band.fill()
        for (index, marker) in sections.enumerated() {
            let end = index + 1 < sections.count ? sections[index + 1].at : project.duration
            let rect = CGRect(
                x: 105 + Double(marker.at) * scale, y: 25,
                width: max(3, Double(max(marker.at, end) - marker.at) * scale - 1), height: 20)
            guard rect.intersects(dirtyRect) else { continue }
            (index.isMultiple(of: 2) ? NSColor.systemIndigo : NSColor.systemPurple)
                .withAlphaComponent(0.42).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            (marker.label as NSString).draw(
                in: rect.insetBy(dx: 5, dy: 3),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.white,
                ])
        }
        ("Sections" as NSString).draw(
            in: CGRect(x: 8, y: 27, width: 92, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray,
            ])
    }
    private func drawBeatGrid(_ dirtyRect: CGRect) {
        NSColor.systemOrange.withAlphaComponent(0.28).setStroke()
        for frame in project.beatFrames {
            let x = 105 + Double(frame) * scale
            guard x >= dirtyRect.minX, x <= dirtyRect.maxX else { continue }
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: 47))
            line.line(to: CGPoint(x: x, y: bounds.height))
            line.stroke()
        }
    }
    private func drawWaveform(item: Item, rect: CGRect, dirtyRect: CGRect) {
        guard let media = project.media.first(where: { $0.id == item.mediaID }),
            let waveform = waveforms[media.id], waveform.hasAudio
        else { return }
        let visible = rect.intersection(dirtyRect).intersection(visibleRect)
        guard !visible.isNull else { return }
        let path = NSBezierPath()
        let sourceStart = Double(item.sourceIn) / media.fps.value
        let secondsPerPoint = item.speed / (project.fps.value * scale)
        for x in stride(from: visible.minX, through: visible.maxX, by: 2) {
            let start = sourceStart + (x - rect.minX) * secondsPerPoint
            let peak = waveform.peak(from: start, to: start + 2 * secondsPerPoint)
            let height = max(0.5, Double(peak) * 10)
            path.move(to: CGPoint(x: x, y: rect.midY - height))
            path.line(to: CGPoint(x: x, y: rect.midY + height))
        }
        NSColor.white.withAlphaComponent(item["muted"] == .bool(true) ? 0.1 : 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func fillColor(track: Track, item: Item) -> NSColor {
        if track.kind == "text" { return .systemYellow.withAlphaComponent(0.5) }
        if track.kind == "audio" {
            return track.role == "music"
                ? .systemOrange.withAlphaComponent(0.5) : .systemGreen.withAlphaComponent(0.5)
        }
        switch item["tag"]?.object["role"]?.string {
        case "speech": return .systemBlue
        case "underVO": return .systemPurple
        default: return .systemTeal
        }
    }
    private func drawLine(frame: Int, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        let x = 105 + Double(frame) * scale
        path.move(to: CGPoint(x: x, y: 0))
        path.line(to: CGPoint(x: x, y: bounds.height))
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard !document.busy, !document.conflict else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let marker = sectionHit(at: point) {
            sectionDrag = marker
            dragRevision = document.project.revision
            dragFrame = marker.at
            document.timelineGestureActive = true
            return
        }
        let row = Int((point.y - 52) / 35)
        if orderedTracks.indices.contains(row) { document.selectedTrackID = orderedTracks[row].id }
        if let hit = hit(at: point) {
            document.selectedID = hit.1.id
            let edge: BashCutProject.Edge? =
                point.x - hit.0.minX < 7 ? .start : hit.0.maxX - point.x < 7 ? .end : nil
            dragState = (hit.1, hit.2, point, edge)
            rolling = edge != nil && event.modifierFlags.contains(.option)
            slipping = edge == nil && event.modifierFlags.contains(.command) && hit.2.kind != "text"
            dragRevision = document.project.revision
            document.timelineGestureActive = true
        } else {
            document.selectedID = nil
            dragState = nil
        }
        document.seek(Int(max(0, point.x - 105) / scale))
    }
    override func mouseDragged(with event: NSEvent) {
        if sectionDrag != nil {
            let point = convert(event.locationInWindow, from: nil)
            dragFrame = min(project.duration, max(0, Int(((point.x - 105) / scale).rounded())))
            needsDisplay = true
            return
        }
        guard let dragState else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = Int(((point.x - dragState.origin.x) / scale).rounded())
        if slipping {
            updateSlip(delta: delta, item: dragState.item)
            return
        }
        var frame = max(0, (dragState.edge == .end ? dragState.item.end : dragState.item.at) + delta)
        if document.ui.snapping && !event.modifierFlags.contains(.command) {
            let candidates =
                project.tracks.flatMap(\.items).filter { $0.id != dragState.item.id }.flatMap {
                    [$0.at, $0.end]
                } + [playhead] + project.beatFrames
            if let nearest = candidates.min(by: { abs($0 - frame) < abs($1 - frame) }),
                Double(abs(nearest - frame)) * scale < 8
            {
                frame = nearest
            }
        }
        dragFrame = frame
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer {
            dragState = nil
            sectionDrag = nil
            dragFrame = nil
            slipSourceIn = nil
            document.timelineGestureActive = false
            needsDisplay = true
        }
        if let section = sectionDrag, let frame = dragFrame {
            guard document.project.revision == dragRevision else {
                document.message = String(localized: "Timeline changed during the gesture; try again.")
                return
            }
            document.apply(
                .upsertSection(id: section.id, label: section.label, atFrame: frame),
                label: "Move section")
            return
        }
        guard let dragState, let frame = dragFrame else { return }
        let gesture = slipping ? "slip" : rolling ? "roll" : dragState.edge.map { "trim-\($0)" } ?? "move"
        DebugLog.write(
            "timeline", "\(gesture) \(dragState.item.id) from \(dragState.track.id)@\(dragState.item.at) to frame \(frame) "
                + "row=\(Int((convert(event.locationInWindow, from: nil).y - 52) / 35))")
        guard document.project.revision == dragRevision else {
            DebugLog.write("timeline", "gesture dropped: revision changed \(dragRevision)→\(document.project.revision)")
            document.message = String(localized: "Timeline changed during the gesture; try again.")
            return
        }
        if slipping, let slipSourceIn {
            document.apply(.slip(item: dragState.item.id, sourceIn: slipSourceIn), label: "Slip clip")
            return
        }
        if rolling, let edge = dragState.edge {
            document.apply(.roll(item: dragState.item.id, edge: edge, toFrame: frame), label: "Roll cut")
            return
        }
        if let edge = dragState.edge {
            document.apply(
                .trim(
                    item: dragState.item.id, edge: edge, toFrame: frame,
                    ripple: dragState.track.role == "main"), label: "Trim clip")
        } else {
            let point = convert(event.locationInWindow, from: nil)
            let row = min(orderedTracks.count - 1, max(0, Int((point.y - 52) / 35)))
            let destination = orderedTracks[row]
            if destination.id == dragState.track.id, destination.magnetic {
                let before = destination.items
                    .filter { $0.id != dragState.item.id }
                    .sorted { $0.at < $1.at }
                    .first { frame < $0.at + $0.duration / 2 }?.id
                document.apply(
                    .reorder(item: dragState.item.id, before: before), label: "Reorder clip")
            } else {
                do { try document.moveItem(dragState.item.id, to: destination.id, at: frame) } catch {
                    document.message = error.localizedDescription
                }
            }
        }
    }
    private func updateSlip(delta: Int, item: Item) {
        guard let media = project.media.first(where: { $0.id == item.mediaID }) else { return }
        let offset = Double(delta) / project.fps.value * media.fps.value * item.speed
        let consumed = Double(item.duration) / project.fps.value * media.fps.value * item.speed
        let maximum = max(0, Int((Double(media.frames) - consumed + 0.0001).rounded(.down)))
        slipSourceIn = min(maximum, max(0, item.sourceIn + Int(offset.rounded())))
        dragFrame = item.at
        document.message = String(format: String(localized: "Source in: %d frames"), slipSourceIn ?? 0)
        needsDisplay = true
    }

    private func hit(at point: CGPoint) -> (CGRect, Item, Track)? {
        // Hit testing is independent of the latest dirty drawing region (scrolling repaints only a strip).
        for (row, track) in orderedTracks.enumerated() {
            for item in track.items.reversed() {
                let rect = CGRect(
                    x: 105 + Double(item.at) * scale, y: Double(row) * 35 + 52,
                    width: max(3, Double(item.duration) * scale - 2), height: 29)
                if rect.contains(point) { return (rect, item, track) }
            }
        }
        return nil
    }
    private func sectionHit(at point: CGPoint) -> TimelineMarker? {
        guard (22...48).contains(point.y) else { return nil }
        return project.sectionMarkers.min(by: {
            abs(105 + Double($0.at) * scale - point.x)
                < abs(105 + Double($1.at) * scale - point.x)
        }).flatMap { abs(105 + Double($0.at) * scale - point.x) <= 7 ? $0 : nil }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dragState = nil
            sectionDrag = nil
            dragFrame = nil
            slipSourceIn = nil
            document.timelineGestureActive = false
            needsDisplay = true
        } else if event.keyCode == 51 {
            document.run(event.modifierFlags.contains(.shift) ? .lift : .delete)
        } else if event.charactersIgnoringModifiers == "s" {
            document.run(.split)
        } else {
            super.keyDown(with: event)
        }
    }
}

private extension TimelineCanvas {
    func updateReviewWarnings(for project: Project) {
        guard project.revision != reviewRevision else { return }
        reviewRevision = project.revision
        voiceoverWarningIDs = Set(
            TimelineReview.run(project).compactMap { issue in
                issue.id.hasPrefix("overlap-") ? String(issue.id.dropFirst("overlap-".count)) : nil
            })
    }

    func drawVoiceoverWarning(
        track: Track, item: Item, path: NSBezierPath, rect: CGRect, warningIDs: Set<String>
    ) {
        guard track.role == "voiceover", warningIDs.contains(item.id) else { return }
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
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
            ])
    }
}
