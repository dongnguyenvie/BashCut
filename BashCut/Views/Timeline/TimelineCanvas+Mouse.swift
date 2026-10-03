import AppKit
import BashCutAutomation
import BashCutProject

/// Pointer and keyboard handling: scrubbing the playhead, moving and trimming clips, hover feedback,
/// the clip context menu and timeline keys. Drags update overlays only; the edit is committed on release.
extension TimelineCanvas {
    /// Pointer distance that grabs the playhead line or a clip edge.
    static let playheadGrab = 4.0
    static let edgeGrab = 7.0
    static let snapDistance = 8.0

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard gesture == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let onPlayhead = grabsPlayhead(point)
        playheadView.highlighted = onPlayhead
        if point.y < TimelineLayout.rulerHeight, point.x >= TimelineLayout.leading {
            showBadge(Timecode.string(min(project.duration, layout.frame(at: point.x)), fps: project.fps), at: point)
        } else if onPlayhead {
            showBadge(Timecode.string(playhead, fps: project.fps), at: point)
        } else {
            badge.show(nil, nearX: 0, y: 0, within: visibleRect)
        }
        let clip = onPlayhead ? nil : hit(at: point)
        hoveredItemID = clip?.1.id
        if onPlayhead || clip.map({ !$0.2.isLocked && edge(at: point, of: $0.0) != nil }) == true {
            hoverCursor = .resizeLeftRight
        } else if let clip, !clip.2.isLocked {
            hoverCursor = .openHand
        } else {
            hoverCursor = .arrow
        }
        hoverCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard gesture == nil else { return }
        hoveredItemID = nil
        playheadView.highlighted = false
        badge.show(nil, nearX: 0, y: 0, within: visibleRect)
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) { hoverCursor.set() }

    func grabsPlayhead(_ point: CGPoint) -> Bool {
        if point.y < TimelineLayout.rulerHeight { return point.x >= TimelineLayout.leading }
        guard abs(point.x - layout.x(playhead)) <= Self.playheadGrab else { return false }
        // A clip edge under the playhead stays trimmable.
        if let clip = hit(at: point), edge(at: point, of: clip.0) != nil { return false }
        return true
    }

    func edge(at point: CGPoint, of rect: CGRect) -> BashCutProject.Edge? {
        point.x - rect.minX < Self.edgeGrab ? .start : rect.maxX - point.x < Self.edgeGrab ? .end : nil
    }

    func showBadge(_ text: String, at point: CGPoint) {
        var visible = visibleRect
        visible.origin.x += TimelineLayout.leading
        visible.size.width -= TimelineLayout.leading
        badge.show(text, nearX: point.x, y: max(visible.minY + 2, point.y - 24), within: visible)
    }

    // MARK: Snapping

    /// `frame` moved to the nearest clip edge, section, beat (or the playhead) within a few points, unless
    /// snapping is off or ⌘ is held.
    func snap(
        _ frame: Int, excluding itemID: String?, toPlayhead: Bool, modifiers: NSEvent.ModifierFlags
    ) -> (frame: Int, snapped: Bool) {
        guard document.ui.snapping, !modifiers.contains(.command) else { return (frame, false) }
        var candidates = project.tracks.flatMap(\.items).filter { $0.id != itemID }.flatMap { [$0.at, $0.end] }
        candidates += project.sectionMarkers.map(\.at) + project.beatFrames + [0, project.duration]
        if toPlayhead { candidates.append(playhead) }
        // The selected clip's keys, so the playhead lands on one to change it.
        if let selected = selectedID.flatMap(locate)?.1, let motion = selected.motion {
            candidates += motion.keyedFrames.filter { (0..<selected.duration).contains($0) }.map { selected.at + $0 }
        }
        guard let nearest = candidates.min(by: { abs($0 - frame) < abs($1 - frame) }),
            Double(abs(nearest - frame)) * scale < Self.snapDistance
        else { return (frame, false) }
        return (nearest, true)
    }

    // MARK: Gestures

    override func mouseDown(with event: NSEvent) {
        guard !document.busy, !document.conflict else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        dragRevision = document.project.revision
        if grabsPlayhead(point) {
            gesture = .playhead
            NSCursor.resizeLeftRight.set()
            scrub(to: point, event: event)
            return
        }
        if let marker = sectionHit(at: point) {
            gesture = .section(marker)
            dragFrame = marker.at
            document.timelineGestureActive = true
            return
        }
        if let row = layout.row(at: point.y) { document.selectedTrackID = row.track.id }
        if let (rect, item, track) = hit(at: point) {
            document.selectedID = item.id
            selectedGap = nil
            guard !track.isLocked else {
                document.message = String(format: String(localized: "%@ is locked"), track.name)
                return
            }
            let edge = edge(at: point, of: rect)
            gesture = .clip(ClipDrag(
                item: item, track: track, origin: point, edge: edge,
                rolling: edge != nil && event.modifierFlags.contains(.option),
                slipping: edge == nil && event.modifierFlags.contains(.command) && track.kind != "text"))
            (edge == nil ? NSCursor.closedHand : NSCursor.resizeLeftRight).set()
            ghost.begin(image: edge == nil ? capture(rect) : nil, outlineOnly: edge != nil)
            document.timelineGestureActive = true
            return
        }
        document.selectedID = nil
        selectedGap = gapHit(at: point)
        document.preview.seek(min(project.duration, layout.frame(at: point.x)))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch gesture {
        case .playhead:
            scrub(to: point, event: event)
        case .section:
            let target = snap(min(project.duration, layout.frame(at: point.x)), excluding: nil, toPlayhead: true, modifiers: event.modifierFlags)
            dragFrame = target.frame
            showGuides(at: target.frame, snapped: target.snapped)
            showBadge(Timecode.string(target.frame, fps: project.fps), at: point)
        case .clip(let drag):
            dragClip(drag, to: point, event: event)
        case nil:
            return
        }
        autoscroll(with: event)
    }

    private func scrub(to point: CGPoint, event: NSEvent) {
        let target = snap(min(project.duration, layout.frame(at: point.x)), excluding: nil, toPlayhead: false, modifiers: event.modifierFlags)
        document.preview.seek(target.frame)
        placePlayhead(target.frame)
        snapGuide.show(atX: target.snapped ? layout.x(target.frame) : nil, height: bounds.height)
        showBadge(Timecode.string(target.frame, fps: project.fps), at: CGPoint(x: point.x, y: TimelineLayout.rulerHeight + 26))
    }

    private func dragClip(_ drag: ClipDrag, to point: CGPoint, event: NSEvent) {
        let delta = Int(((point.x - drag.origin.x) / scale).rounded())
        if drag.slipping {
            updateSlip(delta: delta, item: drag.item)
            showBadge(String(format: String(localized: "Source in: %d frames"), slipSourceIn ?? 0), at: point)
            return
        }
        (drag.edge == nil ? NSCursor.closedHand : NSCursor.resizeLeftRight).set()
        let start = drag.edge == .end ? drag.item.end : drag.item.at
        let target = snap(max(0, start + delta), excluding: drag.item.id, toPlayhead: true, modifiers: event.modifierFlags)
        dragFrame = target.frame
        showGuides(at: target.frame, snapped: target.snapped)
        showGhost(drag, frame: target.frame, pointer: point)
        switch drag.edge {
        case .start:
            showBadge(Timecode.duration(drag.item.end - target.frame, fps: project.fps)
                + "  " + Timecode.delta(target.frame - drag.item.at, fps: project.fps), at: point)
        case .end:
            showBadge(Timecode.duration(target.frame - drag.item.at, fps: project.fps)
                + "  " + Timecode.delta(target.frame - drag.item.end, fps: project.fps), at: point)
        case nil:
            let row = layout.row(at: point.y)?.track.name ?? drag.track.name
            showBadge(Timecode.string(target.frame, fps: project.fps) + "  " + row, at: point)
        }
    }

    /// Where the dragged clip would land: its new extent on the layer under the pointer (moves) or on its own
    /// layer (trims and rolls).
    private func showGhost(_ drag: ClipDrag, frame: Int, pointer: CGPoint) {
        let home = layout.row(for: drag.track.id)
        let row = drag.edge == nil ? (layout.row(at: pointer.y) ?? home) : home
        guard let row else { return ghost.show(nil) }
        let (start, end): (Int, Int) = switch drag.edge {
        case .start: (min(frame, drag.item.end - 1), drag.item.end)
        case .end: (drag.item.at, max(frame, drag.item.at + 1))
        case nil: (frame, frame + drag.item.duration)
        }
        ghost.show(NSRect(x: layout.x(start), y: row.y, width: max(3, Double(end - start) * scale - 2), height: row.height))
    }

    /// A picture of the canvas inside `rect`, for the drag ghost.
    private func capture(_ rect: CGRect) -> NSImage? {
        guard let representation = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        cacheDisplay(in: rect, to: representation)
        let image = NSImage(size: rect.size)
        image.addRepresentation(representation)
        return image
    }

    func showGuides(at frame: Int?, snapped: Bool) {
        dropGuide.show(atX: frame.map(layout.x), height: bounds.height)
        snapGuide.show(atX: snapped ? frame.map(layout.x) : nil, height: bounds.height, width: 2)
    }

    override func mouseUp(with event: NSEvent) {
        let finished = gesture
        defer {
            gesture = nil
            dragFrame = nil
            slipSourceIn = nil
            document.timelineGestureActive = false
            showGuides(at: nil, snapped: false)
            ghost.show(nil)
            badge.show(nil, nearX: 0, y: 0, within: visibleRect)
            mouseMoved(with: event)
        }
        switch finished {
        case .section(let section):
            guard let frame = dragFrame, frame != section.at else { return }
            guard document.project.revision == dragRevision else { return gestureDropped() }
            document.apply(.upsertSection(id: section.id, label: section.label, atFrame: frame), label: "Move section")
        case .clip(let drag):
            commitClipDrag(drag, event: event)
        case .playhead, nil:
            return
        }
    }

    private func gestureDropped() {
        DebugLog.write("timeline", "gesture dropped: revision changed \(dragRevision)→\(document.project.revision)")
        document.message = String(localized: "Timeline changed during the gesture; try again.")
    }

    private func commitClipDrag(_ drag: ClipDrag, event: NSEvent) {
        guard let frame = dragFrame else { return }
        let point = convert(event.locationInWindow, from: nil)
        let name = drag.slipping ? "slip" : drag.rolling ? "roll" : drag.edge.map { "trim-\($0)" } ?? "move"
        DebugLog.write("timeline", "\(name) \(drag.item.id) from \(drag.track.id)@\(drag.item.at) to frame \(frame)")
        guard document.project.revision == dragRevision else { return gestureDropped() }
        if drag.slipping, let slipSourceIn {
            document.apply(.slip(item: drag.item.id, sourceIn: slipSourceIn), label: "Slip clip")
        } else if drag.rolling, let edge = drag.edge {
            document.apply(.roll(item: drag.item.id, edge: edge, toFrame: frame), label: "Roll cut")
        } else if let edge = drag.edge {
            document.apply(
                .trim(item: drag.item.id, edge: edge, toFrame: frame, ripple: drag.track.role == TrackRole.main),
                label: "Trim clip")
        } else {
            let destination = (layout.row(at: point.y) ?? layout.rows.last.map { $0 })?.track ?? drag.track
            if destination.id == drag.track.id, destination.magnetic {
                let before = destination.items.filter { $0.id != drag.item.id }.sorted { $0.at < $1.at }
                    .first { frame < $0.at + $0.duration / 2 }?.id
                document.apply(.reorder(item: drag.item.id, before: before), label: "Reorder clip")
            } else {
                do { try document.moveItem(drag.item.id, to: destination.id, at: frame) } catch {
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
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased()) {
        case (53, _):
            gesture = nil
            dragFrame = nil
            slipSourceIn = nil
            document.timelineGestureActive = false
            showGuides(at: nil, snapped: false)
            ghost.show(nil)
            selectedGap = nil
        case (51, _), (117, _):
            if let gap = selectedGap {
                deleteGap(gap)
            } else {
                document.run(modifiers.contains(.shift) ? .lift : .delete)
            }
        case (123, _), (124, _):
            let back = event.keyCode == 123
            document.run(modifiers.contains(.shift) ? (back ? .backSecond : .forwardSecond) : (back ? .previousFrame : .nextFrame))
        case (_, "s") where modifiers.isEmpty:
            document.run(.split)
        case (_, "z") where modifiers == .shift:
            document.run(.zoomFit)
        case (_, "f") where modifiers == .shift:
            document.run(.freezeFrame)
        case (_, "n") where modifiers.isEmpty:
            document.run(.toggleSnap)
        default:
            super.keyDown(with: event)
        }
    }

    func deleteGap(_ gap: (trackID: String, range: Range<Int>)) {
        do {
            try document.closeGap(at: gap.range.lowerBound, trackID: gap.trackID)
            selectedGap = nil
        } catch { document.message = error.localizedDescription }
    }
}
