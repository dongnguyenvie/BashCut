import AppKit
import BashCutProject

/// What the canvas showed before an update, so the next revision can repaint only what differs.
struct TimelineDrawnState {
    let project: Project
    let layout: TimelineLayout
    let selectedID: String?
    let selectedIDs: Set<String>
    let warnings: Set<String>
    let agentChanges: Set<String>
}

extension TimelineCanvas {
    /// Repainting a clip costs about the same however little changed, and the whole visible timeline was repainted
    /// after every edit (most of the edit time at 1,000 clips). Past this many areas one bounding box is cheaper.
    private static let rectLimit = 64

    /// The areas to repaint after an edit: the old and new place of every clip that changed, gaps that opened or
    /// closed, and clips whose selection, review warning or agent badge changed. Nil when the layers, format,
    /// media, looks or markers changed; then the whole canvas redraws.
    func changedRects(since old: TimelineDrawnState) -> [CGRect]? {
        guard project.sameSettings(as: old.project), layout.sameRows(as: old.layout) else { return nil }
        var rects: [CGRect] = []
        for (row, oldRow) in zip(layout.rows, old.layout.rows) where row.track.items != oldRow.track.items {
            rects += changedRects(in: row, was: oldRow, oldLayout: old.layout)
        }
        // The last section runs to the end of the timeline.
        if project.duration != old.project.duration, !project.sectionMarkers.isEmpty {
            rects.append(CGRect(
                x: 0, y: TimelineLayout.sectionBand.lowerBound, width: bounds.width,
                height: TimelineLayout.sectionBand.upperBound - TimelineLayout.sectionBand.lowerBound))
        }
        var decorated = old.warnings.symmetricDifference(voiceoverWarningIDs)
            .union(old.agentChanges.symmetricDifference(drawnAgentChanges))
        decorated.formUnion(old.selectedIDs.symmetricDifference(selectedIDs))
        if old.selectedID != selectedID { decorated.formUnion([old.selectedID, selectedID].compactMap { $0 }) }
        guard decorated.count <= Self.rectLimit else { return nil }
        rects += decorated.compactMap { locate($0)?.0 }
        // Selection outlines, trim handles and badges reach just past the clip.
        let visible = visibleRect
        rects = rects.map { $0.insetBy(dx: -8, dy: -2) }.filter { $0.intersects(visible) }
        guard rects.count > Self.rectLimit else { return rects }
        return [rects.dropFirst().reduce(rects[0]) { $0.union($1) }]
    }

    /// The old and new place of every clip on one layer that changed, and the gaps that opened or closed there.
    private func changedRects(
        in row: TimelineLayout.Row, was oldRow: TimelineLayout.Row, oldLayout: TimelineLayout
    ) -> [CGRect] {
        var rects: [CGRect] = []
        var previous = Dictionary(oldRow.track.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in row.track.items {
            let before = previous.removeValue(forKey: item.id)
            guard before != item else { continue }
            rects.append(layout.rect(of: item, in: row))
            if let before { rects.append(oldLayout.rect(of: before, in: oldRow)) }
        }
        rects += previous.values.map { oldLayout.rect(of: $0, in: oldRow) }
        if row.track.role == TrackRole.main {
            let gaps = Set(row.track.gaps), oldGaps = Set(oldRow.track.gaps)
            rects += gaps.subtracting(oldGaps).map { layout.rect(ofGap: $0, in: row) }
            rects += oldGaps.subtracting(gaps).map { oldLayout.rect(ofGap: $0, in: oldRow) }
        }
        return rects
    }
}
