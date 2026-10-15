import AppKit
import BashCutAutomation
import BashCutDocument
import SwiftUI

/// Hosts the timeline canvas in a scroll view with the layer header pinned to the left edge. SwiftUI calls
/// `updateNSView` for every playhead change; that only moves the playhead overlay. The canvas redraws when its
/// content (project, zoom, selection, waveforms, size) changes; after an edit, only the clips it touched.
struct TimelineView: NSViewRepresentable {
    let document: ProjectDocument

    /// Everything the canvas draws besides overlays.
    struct ContentKey: Equatable {
        let session: UUID
        let revision: Int
        let scale: Double
        let leading: Double
        let selectedID: String?
        let selectedIDs: [String]
        let selectedTrackID: String?
        let waveforms: Int
        let agentChanges: Int
        let overlays: Int
        let size: CGSize
        let showEmptyTracks: Bool
    }

    func makeNSView(context: Context) -> TimelineContainerView {
        let container = TimelineContainerView(canvas: TimelineCanvas(document: document))
        container.header.onSelect = { [document] id in document.selectedTrackID = id }
        container.header.onResize = { [document] width in document.setTimelineHeaderWidth(width) }
        container.header.onToggleEmpty = { [document] in document.ui.showEmptyTracks.toggle() }
        container.header.onAddMenu = { [document] in
            let menu = NSMenu()
            for (title, action) in [
                (String(localized: "Video Layer"), UIAction.addVideoLayer),
                (String(localized: "Adjustment Layer"), .addAdjustmentLayer),
                (String(localized: "Text Layer"), .addTextLayer),
                (String(localized: "Audio Layer"), .addAudioLayer),
            ] { menu.addItem(ClosureMenuItem(title) { document.run(action) }) }
            return menu
        }
        container.header.onRename = { [document] id, name in
            do { try document.renameLayer(id, to: name) } catch { document.message = error.localizedDescription }
        }
        container.canvas.work.menuFor = { [document] id in TimelineWorkOverlay.menu(document, id: id) }
        container.onUserScroll = { [document] in document.activity.userScrolled() }
        container.header.onMenu = { [document] _ in
            let menu = NSMenu()
            PluginMenus.append(to: menu, document, placement: "track.context")
            return menu.items.isEmpty ? nil : menu
        }
        container.header.onToggle = { [document] id, kind in
            guard let track = document.project.tracks.first(where: { $0.id == id }) else { return }
            do {
                switch kind {
                case .hidden: try document.setLayerSwitches(id, hidden: !track.isHidden)
                case .muted: try document.setLayerSwitches(id, muted: !track.isMuted)
                case .locked: try document.setLayerSwitches(id, locked: !track.isLocked)
                }
            } catch { document.message = error.localizedDescription }
        }
        return container
    }

    func updateNSView(_ container: TimelineContainerView, context: Context) {
        let view = container.scrollView
        let canvas = container.canvas
        let header = container.header
        let project = document.project
        let previousScale = canvas.scale
        let visible = view.documentVisibleRect
        let scale = document.ui.timelineScale / project.fps.value
        document.ui.timelineViewportWidth = view.contentSize.width
        let layout = TimelineLayout(
            project: project, scale: scale, leading: document.ui.timelineLeading,
            expandEmpty: document.ui.showEmptyTracks, keep: document.selectedTrackID)
        let size = CGSize(
            width: max(view.contentSize.width, layout.x(project.duration) + TimelineLayout.trailing),
            height: max(view.contentSize.height, layout.contentHeight))
        let key = ContentKey(
            session: document.sessionID, revision: project.revision, scale: scale, leading: layout.leading,
            selectedID: document.selectedID,
            selectedIDs: document.selectedIDs, selectedTrackID: document.selectedTrackID, waveforms: document.waveforms.values.count,
            agentChanges: document.agentChangedIDs.count, overlays: document.ui.pluginOverlayRevision, size: size,
            showEmptyTracks: document.ui.showEmptyTracks)
        if key != canvas.lastContent {
            if key.session != canvas.lastContent?.session || key.revision != canvas.lastContent?.revision {
                canvas.filmstripURLs.removeAll()
            }
            if key.session != canvas.lastContent?.session { canvas.filmstrips.reset() }
            let previous = canvas.lastContent
            let drawn = TimelineDrawnState(
                project: canvas.project, layout: canvas.layout, selectedID: canvas.selectedID,
                selectedIDs: canvas.selectedIDs,
                warnings: canvas.voiceoverWarningIDs, agentChanges: canvas.drawnAgentChanges)
            canvas.lastContent = key
            canvas.project = project
            canvas.layout = layout
            canvas.updateReviewWarnings(for: project)
            canvas.waveforms = document.waveforms.values
            canvas.selectedID = document.selectedID
            canvas.selectedIDs = Set(document.selectedIDs)
            canvas.drawnAgentChanges = document.agentChangedIDs
            canvas.overlays = document.ui.pluginOverlays
            canvas.setFrameSize(size)
            // An edit or a selection change repaints only the clips it touched.
            if let previous, previous.session == key.session, previous.scale == key.scale, previous.leading == key.leading, previous.size == key.size,
                previous.selectedTrackID == key.selectedTrackID, previous.showEmptyTracks == key.showEmptyTracks,
                previous.waveforms == key.waveforms,
                previous.overlays == key.overlays,
                let rects = canvas.changedRects(since: drawn) {
                rects.forEach(canvas.setNeedsDisplay)
            } else {
                canvas.needsDisplay = true
            }
            header.layout = layout
            if header.frame.width != layout.leading { container.needsLayout = true }
        }
        updateWork(canvas, layout: layout, size: size)
        header.selectedTrackID = document.selectedTrackID
        header.time.text = Timecode.string(document.playhead, fps: project.fps)
        if canvas.gesture == nil || !(canvas.isScrubbing) { canvas.placePlayhead(document.playhead) }
        if let anchor = document.ui.timelineZoomAnchor, anchor != canvas.lastZoomAnchor {
            canvas.lastZoomAnchor = anchor
            keep(anchor, in: view, canvas: canvas, previousScale: previousScale, visible: visible)
        }
        if let reveal = document.ui.timelineReveal, reveal != canvas.lastReveal {
            canvas.lastReveal = reveal
            let x = layout.x(reveal.frame)
            canvas.scrollToVisible(CGRect(x: max(0, x - 120), y: view.documentVisibleRect.minY, width: 240, height: 1))
        }
        follow(document.playhead, in: view, canvas: canvas)
    }

    /// Placeholders, held ranges and the flash of what the agent just changed (#534).
    private func updateWork(_ canvas: TimelineCanvas, layout: TimelineLayout, size: CGSize) {
        if canvas.work.frame.size != size { canvas.work.frame = CGRect(origin: .zero, size: size) }
        let work = TimelineWorkOverlay.content(document, layout: layout)
        canvas.work.update(boxes: work.boxes, held: work.held)
        guard let flash = document.activity.flash, flash.id != canvas.lastFlash else { return }
        canvas.lastFlash = flash.id
        canvas.work.flash(flash.items.compactMap { canvas.locate($0)?.0 })
    }

    /// During playback, turns the page when the playhead leaves the visible area, like CapCut.
    private func follow(_ frame: Int, in view: NSScrollView, canvas: TimelineCanvas) {
        guard document.preview.isPlaying, canvas.gesture == nil else { return }
        let visible = view.documentVisibleRect
        let x = canvas.layout.x(frame)
        let viewport = visible.width - canvas.layout.leading
        guard x > visible.maxX - 24 || x < visible.minX + canvas.layout.leading else { return }
        let maximum = max(0, canvas.frame.width - visible.width)
        let origin = CGPoint(x: min(max(0, x - canvas.layout.leading - viewport * 0.1), maximum), y: visible.minY)
        view.contentView.scroll(to: origin)
        view.reflectScrolledClipView(view.contentView)
    }

    /// Scrolls so the anchor frame sits at the same place in the visible area as before the zoom.
    private func keep(
        _ anchor: TimelineZoomAnchor, in view: NSScrollView, canvas: TimelineCanvas, previousScale: Double,
        visible: CGRect
    ) {
        let oldX = canvas.layout.leading + Double(anchor.frame) * previousScale
        let offset = anchor.viewOffset
            ?? (visible.minX...visible.maxX ~= oldX ? oldX - visible.minX : visible.width / 2)
        let newX = canvas.layout.x(anchor.frame)
        let maximum = max(0, canvas.frame.width - visible.width)
        let origin = CGPoint(x: min(max(0, newX - offset), maximum), y: visible.minY)
        view.contentView.scroll(to: origin)
        view.reflectScrolledClipView(view.contentView)
    }
}

/// The scroll view with the layer header laid over its left edge. The header is a sibling, not a floating
/// subview (that broke SwiftUI rendering of the whole window); it follows vertical scrolling of the clip view.
final class TimelineContainerView: NSView {
    let scrollView = NSScrollView()
    let canvas: TimelineCanvas
    let header = TimelineHeaderView(frame: .zero)

    init(canvas: TimelineCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.documentView = canvas
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)
        addSubview(header)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewScrolled), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(userScrolled), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
    }

    /// Scrolling by the user (not by follow mode or a reveal) ends follow mode (#534).
    var onUserScroll: (() -> Void)?
    @objc private func userScrolled() { onUserScroll?() }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        header.frame = NSRect(
            x: 0, y: 0, width: header.layout.leading, height: scrollView.contentView.frame.height)
        clipViewScrolled()
    }

    @objc private func clipViewScrolled() {
        header.scrollOffset = scrollView.contentView.bounds.origin.y
    }
}
