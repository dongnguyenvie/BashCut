import Foundation
import Observation

/// Editor view state that is not part of the project: timeline zoom and scroll requests, toggles, the
/// open library panel and inspector tab, and which editor sheets are showing. `ui.view`, `ui.panel`,
/// `ui.open` and `ui.dialog` read and change it; nothing here is saved with the project.
@MainActor @Observable
public final class EditorUIState {
    /// Timeline pixels per second: from a whole long video in view to single frames.
    public static let timelineZoomRange: ClosedRange<Double> = 1...600
    public static let zoomStep = 1.25
    /// Width of the track-name column left of frame 0, and the margin kept after the end when fitting.
    public static let timelineLeading = 140.0
    public static let fitMargin = 40.0

    /// Timeline pixels per second.
    public private(set) var timelineScale = 50.0
    public var timelineReveal: TimelineReveal?
    /// The point a zoom keeps in place; the timeline consumes each new request once. Not observed: it is set
    /// with `timelineScale`, whose change already updates the timeline.
    @ObservationIgnored public private(set) var timelineZoomAnchor: TimelineZoomAnchor?
    /// Visible timeline width in points, reported by the timeline view; used to fit the timeline.
    @ObservationIgnored public var timelineViewportWidth = 900.0
    public var snapping = true
    public var showSafeArea = false
    public var showAgentDock = true
    public var libraryTab: LibraryTab = .media
    /// One of `UIAction.inspectorTabs`.
    public var inspectorTab = "video"

    // Editor sheets and popovers; `ModalCenter` reports them to automation.
    public var showNewProject = false
    public var showExport = false
    public var showExportReport = false
    public var showAgentChanges = false
    public var showExternalChanges = false
    public var showLegacyImportReport = false
    public var showReview = false
    public var showHistory = false
    public var showPlugins = false
    public var showSettings = false
    public var showDoctor = false
    public var showAsk = false
    public var showSections = false

    public init() {}

    public var canZoomIn: Bool { timelineScale < Self.timelineZoomRange.upperBound }
    public var canZoomOut: Bool { timelineScale > Self.timelineZoomRange.lowerBound }

    /// Sets the zoom, clamped to the range. With an `anchor` frame the timeline keeps that frame where it is
    /// on screen (`viewOffset` from the left of the visible area, or its current position when nil).
    public func setTimelineZoom(_ value: Double, anchor: Int? = nil, viewOffset: Double? = nil) {
        guard value.isFinite else { return }
        timelineScale = min(max(value, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
        if let anchor { timelineZoomAnchor = TimelineZoomAnchor(frame: max(0, anchor), viewOffset: viewOffset) }
    }

    /// Zoom buttons and shortcuts keep the playhead in place.
    public func zoomIn(around playhead: Int? = nil) { setTimelineZoom(timelineScale * Self.zoomStep, anchor: playhead) }

    public func zoomOut(around playhead: Int? = nil) { setTimelineZoom(timelineScale / Self.zoomStep, anchor: playhead) }

    /// Multiplies the zoom by `factor` around the frame under the pointer (pinch and ⌘-scroll).
    public func magnifyTimeline(by factor: Double, at frame: Int, viewOffset: Double) {
        guard factor.isFinite, factor > 0 else { return }
        setTimelineZoom(timelineScale * factor, anchor: frame, viewOffset: viewOffset)
    }

    /// The slider position: zoom is multiplicative, so the slider moves on a log scale.
    public var timelineZoomSliderValue: Double { log(timelineScale) }
    public static var timelineZoomSliderRange: ClosedRange<Double> {
        log(timelineZoomRange.lowerBound)...log(timelineZoomRange.upperBound)
    }

    public func setTimelineZoomSliderValue(_ value: Double, around playhead: Int? = nil) {
        setTimelineZoom(exp(value), anchor: playhead)
    }

    /// The zoom that shows `duration` frames at `fps` in the visible width, with a margin after the end.
    public func fitZoom(duration: Int, fps: Double) -> Double {
        let seconds = Double(max(1, duration)) / max(1, fps)
        let width = max(100, timelineViewportWidth - Self.timelineLeading - Self.fitMargin)
        return min(max(width / seconds, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
    }

    /// Shows the whole timeline from its start.
    public func zoomToFit(duration: Int, fps: Double) {
        setTimelineZoom(fitZoom(duration: duration, fps: fps), anchor: 0, viewOffset: Self.timelineLeading)
    }

    /// Asks the timeline to scroll `frame` (clamped to `0...duration`) into view.
    public func revealInTimeline(_ frame: Int, duration: Int) {
        timelineReveal = TimelineReveal(frame: min(max(0, frame), max(0, duration)))
    }

    /// Closes the sheets that describe the previous project when another one opens.
    public func closeProjectSheets() {
        showExportReport = false
        showAgentChanges = false
        showExternalChanges = false
        showLegacyImportReport = false
    }

    /// Sheets that open unconditionally by name (`ui.open`).
    public static let toggledDialogs: [String: ReferenceWritableKeyPath<EditorUIState, Bool>] = [
        "review": \.showReview, "history": \.showHistory, "plugins": \.showPlugins, "settings": \.showSettings,
        "doctor": \.showDoctor, "ask": \.showAsk, "sections": \.showSections,
    ]
}

/// A one-off request to keep `frame` at `viewOffset` points from the left of the visible timeline after a zoom.
/// A nil offset keeps the frame where it was before the zoom (centered if it was off screen).
public struct TimelineZoomAnchor: Equatable, Sendable {
    public let frame: Int
    public let viewOffset: Double?
    public let id = UUID()

    public init(frame: Int, viewOffset: Double?) {
        self.frame = frame
        self.viewOffset = viewOffset
    }
}

/// A one-off request for the timeline to scroll a frame into view.
public struct TimelineReveal: Equatable, Sendable {
    public let frame: Int
    public let id = UUID()

    public init(frame: Int) { self.frame = frame }
}

/// Left-rail library panels; `CommandCatalog.libraryPanels` lists their lowercased names.
public enum LibraryTab: String, CaseIterable, Identifiable, Sendable {
    case media = "Media"
    case audio = "Audio"
    case text = "Text"
    case stickers = "Stickers"
    case effects = "Effects"
    case transitions = "Transitions"
    case filters = "Filters"
    case voice = "Voice"

    public var id: String { rawValue }

    /// The automation name (`ui.panel`).
    public var panelName: String { rawValue.lowercased() }

    public init?(panelName: String) {
        guard let tab = Self.allCases.first(where: { $0.panelName == panelName }) else { return nil }
        self = tab
    }

    public var icon: String {
        switch self {
        case .media: return "film"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .stickers: return "star"
        case .effects: return "sparkles"
        case .transitions: return "arrow.left.arrow.right"
        case .filters: return "circle.lefthalf.filled"
        case .voice: return "mic"
        }
    }
}
